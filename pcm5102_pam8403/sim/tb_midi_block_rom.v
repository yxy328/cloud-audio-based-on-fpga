`timescale 1ns/1ps
module tb_midi_block_rom;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;
    reg [55:0] map=0;
    wire [223:0] reference,rom;
    integer n,k;
    midi_note_lut original(.clk(clk),.resetn(resetn),.note_map(map),.phase_increments(reference));
    midi_note_lut #(.BLOCK_ROM(1)) optimized(.clk(clk),.resetn(resetn),.note_map(map),.phase_increments(rom));
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        for(n=0;n<256;n=n+1)begin
            for(k=0;k<7;k=k+1)map[k*8+:8]=(n+k*13)%256;
            repeat(2)@(negedge clk);
            if(rom!==reference)$fatal(1,"Block-ROM LUT mismatch at %0d",n);
        end
        $display("PASS MIDI block ROM: 256 notes on each of seven addresses, exact reference mapping/invalid zero, synchronous read");$finish;
    end
endmodule
