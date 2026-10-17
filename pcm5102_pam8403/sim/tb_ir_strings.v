`timescale 1ns/1ps
module tb_ir_strings;
    reg clk=0, rst_n=0;
    reg [7:0] beam=8'hFF;
    wire [7:0] blocked, armed;
    wire valid;
    wire [2:0] index;
    integer events=0, last_note=-1, before_count, ch, mask, expected_count;
    integer note_history [0:4095];
    reg [7:0] observed_notes;
    always #10 clk=~clk;
    ir_strings #(.FILTER_CYCLES(8)) dut (
        .clk(clk), .rst_n(rst_n), .beam_in(beam), .blocked(blocked),
        .armed(armed), .note_valid(valid), .note_index(index));
    always @(posedge clk) if(rst_n && valid) begin
        note_history[events]=index; events=events+1; last_note=index;
    end
    task settle; begin repeat(32) @(negedge clk); end endtask
    initial begin
        settle; rst_n=1; settle;
        if(events!=0 || armed!=0) $fatal(1,"Startup blocked/unconnected channel triggered");
        // Brief low cannot arm; brief high cannot trigger; repeated glitches
        // must never accumulate toward either stable transition.
        repeat(5) begin beam[0]=0; repeat(3) @(negedge clk); beam[0]=1; settle; end
        if(armed[0] || events) $fatal(1,"Release glitches armed a string");
        beam[0]=0; settle;
        if(!armed[0] || blocked[0]) $fatal(1,"Stable light did not arm");
        repeat(5) begin beam[0]=1; repeat(3) @(negedge clk); beam[0]=0; settle; end
        if(events) $fatal(1,"Short blockage triggered");
        beam[0]=1; settle;
        if(events!=1 || last_note!=0) $fatal(1,"First qualified edge");
        repeat(100) @(negedge clk);
        if(events!=1) $fatal(1,"Held blockage retriggered");
        beam[0]=0; repeat(3) @(negedge clk); beam[0]=1; settle;
        if(events!=1) $fatal(1,"Short release rearmed");
        beam[0]=0; settle; beam[0]=1; settle;
        if(events!=2) $fatal(1,"Clear-and-block did not retrigger");
        for(ch=0;ch<8;ch=ch+1) begin
            before_count=events; beam[ch]=0; settle; beam[ch]=1; settle;
            if(events!=before_count+1 || last_note!=ch) $fatal(1,"String index %0d",ch);
        end
        beam=0; settle; before_count=events; beam=8'hFF; settle;
        if(events!=before_count+8 || last_note!=7 || armed!=0)
            $fatal(1,"Simultaneous edges must retain all eight strings");
        for(ch=0;ch<8;ch=ch+1)
            if(note_history[before_count+ch]!=ch) $fatal(1,"Eight-string dispatch order");
        // Exhaust every subset, including non-adjacent chord notes and no
        // blockage. A held subset must not repeat after its queue drains.
        for(mask=0;mask<256;mask=mask+1) begin
            beam=0; settle; before_count=events; expected_count=0;
            beam=mask; settle;
            for(ch=0;ch<8;ch=ch+1) if(mask & (1<<ch)) begin
                if(note_history[before_count+expected_count]!=ch)
                    $fatal(1,"Subset %02x lost/reordered string %0d",mask,ch);
                expected_count=expected_count+1;
            end
            if(events!=before_count+expected_count) $fatal(1,"Subset %02x count",mask);
            settle;
            if(events!=before_count+expected_count) $fatal(1,"Held subset retriggered");
        end
        // New qualified bits arrive while previously qualified bits drain.
        beam=0; settle; before_count=events;
        beam=8'hF0; @(negedge clk); beam=8'hFF; settle;
        if(events!=before_count+8) $fatal(1,"Overlapping dispatch lost a note");
        observed_notes=0;
        for(ch=0;ch<8;ch=ch+1) begin
            if(observed_notes[note_history[before_count+ch]]) $fatal(1,"Overlapping dispatch duplicated a note");
            observed_notes[note_history[before_count+ch]]=1;
        end
        if(observed_notes!=8'hFF) $fatal(1,"Overlapping dispatch incomplete");
        // Reset cancels undelivered events; a blocked input cannot rearm.
        beam=0; settle; beam=8'hFF; wait(valid); @(negedge clk);
        rst_n=0; before_count=events; settle; rst_n=1; settle;
        if(events!=before_count || armed!=0 || dut.pending_notes!=0)
            $fatal(1,"Reset failed to cancel queued notes");
        before_count=events;
        rst_n=0; settle; rst_n=1; settle;
        if(events!=before_count || armed!=0) $fatal(1,"Reset while blocked triggered");
        $display("PASS IR startup/filter/rearm, all 256 simultaneous subsets, overlapping dispatch, held blockage and reset cancellation");
        $finish;
    end
    initial begin #1_000_000; $fatal(1,"IR unit timeout"); end
endmodule
