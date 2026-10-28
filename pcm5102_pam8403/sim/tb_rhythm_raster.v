`timescale 1ns/1ps
module tb_rhythm_raster;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,tick=0,spawn=0,long_note=0;
    reg [11:0] keys=0;reg [15:0] delay_ms=1500;
    wire ready,overflow;
    hub75e_rhythm_display #(.CONTROL_KEYS(12),.ENABLE_GAME(1)) dut(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(tick),.note_spawn(spawn),
        .spawn_keys(keys),.spawn_delay_ms(delay_ms),.game_spawn_long(long_note),
        .game_spawn_type(long_note ? 2'd1 : 2'd0),.game_spawn_body(1'b0),.game_event_type(2'd0),.game_gesture(1'b0),
        .game_settings(8'he4),.game_event_start(1'b0),.game_event_end(1'b0),.game_event_duration(16'd0),
        .guide_keys(12'd0),.touch_keys(12'd0),.touch_mode16(1'b1),.all_touch_keys(16'd0),
        .visual_mode(2'd0),.note_ready(ready),.overflow(overflow));
    reg [35:0] model[0:63];integer phase=0,advance,y,i,accepted=0,blocked=0;
    always @(posedge clk)begin
        if(!resetn || !playing)begin phase=0;for(i=0;i<64;i=i+1)model[i]=0;end
        else begin
            advance=phase+(tick ? 52 : 0);
            if(advance>=1500)begin
                advance=advance-1500;
                for(i=63;i>0;i=i-1)model[i]=model[i-1];model[0]=0;
            end
            phase=advance;
            if(spawn)begin
                y=54-(phase+delay_ms*52)/1500;
                model[y]=model[y] | {long_note ? keys : 12'd0,keys};accepted=accepted+1;
            end
        end
    end
    task compare;
        begin repeat(8)@(negedge clk);wait(!dut.clear_pending);
            for(i=0;i<64;i=i+1)if(dut.note_rows[i]!==model[i])$fatal(1,"raster row%0d got%h expected%h",i,dut.note_rows[i],model[i]);
            if(overflow)$fatal(1,"raster overflow");
        end
    endtask
    task elapse;
        input integer count;integer n;
        begin for(n=0;n<count;n=n+1)begin
            @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(14)@(negedge clk);
        end compare;end
    endtask
    task submit;
        input [11:0] k;input long;input [15:0] delay;
        begin wait(ready);@(negedge clk);keys=k;long_note=long;delay_ms=delay;spawn=1;
            @(negedge clk);spawn=0;compare;end
    endtask
    integer n;
    initial begin
        repeat(4)@(negedge clk);resetn=1;playing=1;wait(ready);compare;
        submit(1,0,1500);elapse(500);submit(12'h800,1,750);elapse(1000);elapse(5000);
        for(n=0;n<1000;n=n+1)begin
            @(negedge clk);tick=(n%16==0);spawn=ready;keys=12'b1<<(n%12);long_note=n%2;delay_ms=1500;
            if(!ready)blocked=blocked+1;
        end
        @(negedge clk);spawn=0;tick=0;compare;
        if(blocked==0 || accepted<900)$fatal(1,"clear backpressure not exercised %0d/%0d",blocked,accepted);
        @(negedge clk);playing=0;@(negedge clk);playing=1;wait(ready);compare;
        $display("PASS game raster: 64-row independent model, 6500ms wrap/clear, tap+hold planes, %0d dense accepted heads, %0d backpressure clocks, STOP/reinitialize",accepted,blocked);$finish;
    end
    initial begin #10000000;$fatal(1,"raster timeout");end
endmodule
