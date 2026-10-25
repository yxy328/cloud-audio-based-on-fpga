`timescale 1ns/1ps
module tb_score_decoder;
    downloadable_song candidate(.clk(1'b0),.resetn(1'b0));
    downloadable_song_reference reference(.clk(1'b0),.resetn(1'b0));
    reg [55:0] mapping;
    reg [12:0] mask;
    integer key_index, pitch_value, bit_index, i, count=0;
    reg [31:0] random_state=32'h4c29ab37;
    function [31:0] next_random;
        input [31:0] x;
        reg [31:0] y;
        begin y=x^(x<<13); y=y^(y>>17); next_random=y^(y<<5); end
    endfunction
    task check;
        begin
            candidate.checked_map=mapping; reference.checked_map=mapping;
            candidate.fetched={mask,16'd1}; reference.fetched={mask,16'd1};
            #1;
            if(candidate.covered_mask !== reference.covered_mask ||
               candidate.fetched_keys !== reference.fetched_keys)
                $fatal(1,"decoder mismatch map=%h mask=%h",mapping,mask);
            count=count+1;
        end
    endtask
    initial begin
        // Every byte value in every lane, for each independent input mask bit.
        // This includes invalid MIDI values and all seven physical positions.
        for(key_index=0;key_index<7;key_index=key_index+1)
            for(pitch_value=0;pitch_value<256;pitch_value=pitch_value+1)
                for(bit_index=0;bit_index<13;bit_index=bit_index+1) begin
                    mapping=0; mapping[key_index*8 +: 8]=pitch_value;
                    mask=13'b1<<bit_index; check;
                end
        mapping={8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
        for(i=0;i<8192;i=i+1) begin mask=i;check;end
        // Mixed maps, duplicates, invalid bytes and chords/rests.
        for(i=0;i<20000;i=i+1) begin
            random_state=next_random(random_state); mapping[31:0]=random_state;
            random_state=next_random(random_state); mapping[55:32]=random_state[23:0];
            random_state=next_random(random_state); mask=random_state[12:0];check;
        end
        $display("PASS decoder equivalence: %0d vectors",count);
        $finish;
    end
endmodule
