`timescale 1ns/1ps
// User-reported pair: key1 must survive line disturbances on key7, but
// a genuinely reported 1+7 chord must still produce both note events.
module tb_ttp229_key1_key7;
    reg clk=0,rst_n=0,flip=0,inject=0;
    reg [15:0] keys=0;
    wire scl,sensor_sdo,valid,scan_valid,scan_error;
    wire sdo=sensor_sdo ^ flip;
    wire [15:0] down,raw;
    wire [3:0] index;
    integer wire_bit=0,events=0,bad=0,key1_events=0,key7_events=0;
    always #10 clk=~clk;
    ttp229_keys #(.STARTUP_CYCLES(8)) dut(
        .clk(clk),.rst_n(rst_n),.sdo(sdo),.scl(scl),.keys_down(down),
        .raw_keys(raw),.scan_valid(scan_valid),.scan_error(scan_error),
        .note_valid(valid),.note_index(index),.note_ready(1'b1));
    ttp229_model sensor(.rst_n(rst_n),.scl(scl),.connected(1'b1),
        .dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(sensor_sdo));
    always @(posedge clk) if(rst_n) begin
        if(valid) begin
            events=events+1;
            if(index==0) key1_events=key1_events+1;
            else if(index==6) key7_events=key7_events+1;
            else $fatal(1,"Unexpected note index %0d",index);
        end
        if(scan_valid && scan_error) bad=bad+1;
    end
    always @(negedge scl) if(rst_n) wire_bit=(wire_bit+1)%16;
    always @(negedge scl) begin
        #1;
        if(rst_n && inject && wire_bit==7) begin
            #9600;flip=1;#600;flip=0;#9400;flip=1;#600;flip=0;
        end
    end
    task scans(input integer n);
        integer f;
        begin for(f=0;f<n;f=f+1) begin
            @(posedge scan_valid);repeat(40) @(negedge clk);
        end end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;scans(3);
        keys=1;scans(2);inject=1;scans(4);inject=0;
        if(down!=1 || raw!=16'h0001 || events!=1 || key7_events || bad!=0)
            $fatal(1,"False key7 while holding key1: raw=%h down=%h notes=%0d bad=%0d",raw,down,events,bad);
        scans(2);keys=16'h0041;scans(2);
        if(down!=16'h0041 || events!=2 || key1_events!=1 || key7_events!=1)
            $fatal(1,"Real 1+7 chord suppressed");
        keys=16'h0040;scans(2);
        if(down!=16'h0040 || events!=2) $fatal(1,"Independent key1 release failed");
        keys=16'h0041;scans(2);
        if(events!=3 || key1_events!=2 || key7_events!=1) $fatal(1,"Key1 rearm repeated key7");
        $display("PASS user key1/key7 case: four disturbed frames corrected to RAW=0001 DOWN=0001, genuine 1+7 chord and separate release/re-press preserved");
        $finish;
    end
    initial begin #75000000;$fatal(1,"Key1/key7 test timeout");end
endmodule
