`timescale 1ns/1ps
module tb_hub75e_ram_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,ms_tick=0,note_spawn=0;
    reg [6:0] touch_keys=0,guide_keys=0,spawn_keys=0;
    reg [15:0] spawn_delay_ms=0;
    reg touch_mode16=0;
    reg [15:0] all_touch_keys=0;
    wire [13:0] actual,expected;
    wire ready,reference_ready,overflow,reference_overflow;
    hub75e_rhythm_display #(.LEAD_MS(64)) dut(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.touch_keys(touch_keys),
        .guide_keys(guide_keys),.touch_mode16(touch_mode16),.all_touch_keys(all_touch_keys),
        .visual_mode(2'd0),.sample_ce(1'b0),.mixed_sample(16'd0),.touch0(16'd0),
        .touch1(16'd0),.sensor_sample(16'd0),.guitar_sample(16'd0),
        .note_ready(ready),.overflow(overflow),
        .hub_R1(actual[13]),.hub_G1(actual[12]),.hub_B1(actual[11]),
        .hub_R2(actual[10]),.hub_G2(actual[9]),.hub_B2(actual[8]),
        .hub_A(actual[7]),.hub_B(actual[6]),.hub_C(actual[5]),.hub_D(actual[4]),.hub_E(actual[3]),
        .hub_CK(actual[2]),.hub_ST(actual[1]),.hub_OE(actual[0]));
    hub75e_rhythm_display_reference #(.LEAD_MS(64)) reference(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.touch_keys(touch_keys),
        .guide_keys(guide_keys),.touch_mode16(touch_mode16),.all_touch_keys(all_touch_keys),
        .visual_mode(2'd0),.sample_ce(1'b0),.mixed_sample(16'd0),.touch0(16'd0),
        .touch1(16'd0),.sensor_sample(16'd0),.guitar_sample(16'd0),
        .note_ready(reference_ready),.overflow(reference_overflow),
        .hub_R1(expected[13]),.hub_G1(expected[12]),.hub_B1(expected[11]),
        .hub_R2(expected[10]),.hub_G2(expected[9]),.hub_B2(expected[8]),
        .hub_A(expected[7]),.hub_B(expected[6]),.hub_C(expected[5]),.hub_D(expected[4]),.hub_E(expected[3]),
        .hub_CK(expected[2]),.hub_ST(expected[1]),.hub_OE(expected[0]));
    integer n,row,checks=0;
    reg [31:0] random=32'h1bfb327d;
    always @(posedge clk)begin
        #1;
        if(actual!==expected || ready!==reference_ready || overflow!==reference_overflow)
            $fatal(1,"Display pin/control mismatch cycle=%0d actual=%h expected=%h",n,actual,expected);
        if(resetn)begin
            for(row=0;row<64;row=row+1)
                if(dut.note_rows[row]!==reference.note_rows[row])
                    $fatal(1,"Circular bitmap mismatch cycle=%0d row=%0d",n,row);
            if(dut.upper_notes!==reference.upper_notes || dut.lower_notes!==reference.lower_notes)
                $fatal(1,"Display RAM prefetch mismatch cycle=%0d row=%0d",n,dut.scan_row);
            checks=checks+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);
        for(n=0;n<180000;n=n+1)begin
            random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
            resetn=n%7919>3;playing=n%1024<1015;
            ms_tick=random[0];note_spawn=n%256<128 || random[1];
            spawn_keys=random[8:2];spawn_delay_ms=random[15:9]%81;
            touch_keys=random[22:16];guide_keys=random[29:23];
            touch_mode16=random[30];all_touch_keys=random[31:16];
            @(negedge clk);
        end
        $display("PASS circular display: %0d cycle/pin checks and full 64-row comparisons, dense 128-clock bursts, consecutive scrolls, OR forwarding, STOP/reset races",checks);$finish;
    end
endmodule
