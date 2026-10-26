`timescale 1ns/1ps
module tb_map_decode_exhaustive;
    reg clk=0,resetn=0;
    reg [55:0] mapping;
    reg [12:0] mask;
    integer lane,pitch,n,j,checks=0;
    reg [31:0] random=32'h65ea17bc;
    downloadable_song #(.ENABLE_LOOKAHEAD(1)) dut(.clk(clk),.resetn(resetn));
    downloadable_song_pack_reference #(.ENABLE_LOOKAHEAD(1)) reference(.clk(clk),.resetn(resetn));
    task inspect;
        begin
            dut.checked_map=mapping;reference.checked_map=mapping;
            dut.fetched={mask,16'd1};reference.fetched={mask,16'd1};
            #1;
            if(dut.covered_mask!==reference.covered_mask || dut.fetched_keys!==reference.fetched_keys)
                $fatal(1,"Map decode mismatch mapping=%h mask=%h covered=%h/%h keys=%h/%h",mapping,mask,
                       dut.covered_mask,reference.covered_mask,dut.fetched_keys,reference.fetched_keys);
            checks=checks+1;
        end
    endtask
    initial begin
        // Every possible byte value in every lane, with each single note,
        // all notes and a rest. Includes duplicate and out-of-range mappings.
        for(lane=0;lane<7;lane=lane+1)
            for(pitch=0;pitch<256;pitch=pitch+1)begin
                mapping={8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
                mapping[lane*8 +: 8]=pitch;
                mask=0;inspect;
                mask=8191;inspect;
                for(n=0;n<13;n=n+1)begin mask=1<<n;inspect;end
            end
        // Every chord mask with a changing mix of legal, illegal and
        // repeated map bytes; independent old variable-select reference.
        for(n=0;n<8192;n=n+1)begin
            for(j=0;j<7;j=j+1)begin
                random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
                mapping[j*8 +: 8]=random[0] ? 60+random[15:8]%13 : random[15:8];
            end
            mask=n;inspect;
        end
        $display("PASS map decode: %0d cases, every byte/lane and every 13-bit chord mask, duplicates and invalid mapping bytes",checks);
        $finish;
    end
endmodule
