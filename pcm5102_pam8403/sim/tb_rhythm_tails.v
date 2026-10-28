`timescale 1ns/1ps
module tb_rhythm_tails;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,request=0;reg [2:0] op=0;
    reg [15:0] arg0=0,arg1=0,arg2=0;
    wire done,playing,tick,spawn,body,ready,event_start,event_end;
    wire [2:0] error;wire [11:0] spawn_keys,guide_keys;
    wire [15:0] delay_ms,duration;wire [1:0] spawn_type,event_type;
    reg [11:0] touch=0;
    downloadable_song #(.CONTROL_KEYS(12),.TRUSTED_MAP(1),.CLK_HZ(100000),.ENABLE_LOOKAHEAD(1)) song(
        .clk(clk),.resetn(resetn),.request(request),.operation(op),.arg0(arg0),.arg1(arg1),.arg2(arg2),.arg3(16'd0),
        .score_min(16'd8192),.score_max(16'd32768),.edit_allowed(1'b1),
        .note_map({8'd71,8'd70,8'd69,8'd68,8'd67,8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60}),
        .toggle_play(1'b0),.restart(1'b0),.done(done),.error(error),.playing(playing),.ms_tick(tick),
        .note_spawn(spawn),.spawn_keys(spawn_keys),.spawn_delay_ms(delay_ms),.note_ready(ready),
        .spawn_type(spawn_type),.spawn_body(body),.guide_keys(guide_keys),
        .event_start(event_start),.event_end(event_end),.event_type(event_type),.event_duration(duration));
    hub75e_rhythm_display #(.CONTROL_KEYS(12),.ENABLE_GAME(1)) panel(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(tick),.note_spawn(spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(delay_ms),.game_spawn_type(spawn_type),.game_spawn_body(body),
        .game_event_start(event_start),.game_event_end(event_end),.game_event_duration(duration),.game_event_type(event_type),
        .game_settings(8'he4),.game_gesture(1'b0),.guide_keys(guide_keys),.touch_keys(touch),
        .touch_mode16(1'b1),.all_touch_keys({4'd0,touch}),.visual_mode(2'd0),.note_ready(ready));
    task command;
        input [2:0] operation;input [15:0] a0,a1,a2;input [2:0] expected;
        begin @(negedge clk);op=operation;arg0=a0;arg1=a1;arg2=a2;request=1;
            @(negedge clk);request=0;wait(done);@(negedge clk);
            if(error!==expected)$fatal(1,"tail command error op%0d got%0d expected%0d",op,error,expected);
        end
    endtask
    integer i,count,heads,bodies,ms,fd,y,x;reg [14:0] rgb;
    task pixels;
        output integer result;
        begin result=0;repeat(8)@(negedge clk);
            for(i=2;i<=54;i=i+1)if(panel.note_rows[i][12])result=result+1;
        end
    endtask
    task wait_ms;
        input integer n;integer m;
        begin for(m=0;m<n;m=m+1)begin @(posedge tick);@(negedge tick);end repeat(8)@(negedge clk);end
    endtask
    task start_hold;
        input [15:0] length;
        begin command(1,2,0,0,0);command(6,0,16'd16385,length,0);command(6,1,0,500,0);
            command(3,0,0,0,0);command(4,0,0,0,0);wait(event_start);repeat(8)@(negedge clk);end
    endtask
    always @(negedge clk)if(resetn && spawn && body && (spawn_keys!=1 || spawn_type!=1))$fatal(1,"body metadata corrupted");
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        // Invalid type and explicit rest must be rejected before commit.
        command(1,1,0,0,0);command(6,0,16'd40961,100,2);command(6,0,16'd8192,100,2);
        start_hold(600);touch=1;repeat(90)@(negedge clk);
        if(!panel.game_holding)$fatal(1,"tail test HOLD not acquired");
        pixels(count);if(count<20 || count>22)$fatal(1,"600ms tail length %0d",count);
        // Artifact is generated from the RTL shader and real bitmap state.
        fd=$fopen("sim/build/rhythm_tail_600.ppm","w");$fwrite(fd,"P3\n64 64\n31\n");
        for(y=0;y<64;y=y+1)for(x=0;x<64;x=x+1)begin
            rgb=panel.pixel_rgb(x,y,panel.note_rows[y],x/5,x%5,12'd0);$fwrite(fd,"%0d %0d %0d\n",rgb[14:10],rgb[9:5],rgb[4:0]);
        end $fclose(fd);
        wait_ms(300);pixels(count);if(count<10 || count>12)$fatal(1,"tail did not shrink %0d",count);
        wait(event_end);touch=0;wait_ms(40);pixels(count);if(count!=0)$fatal(1,"completed tail still visible %0d",count);
        if(panel.game_score!==24'h001500)$fatal(1,"tail completion score %h",panel.game_score);
        command(5,0,0,0,0);
        start_hold(2300);touch=1;pixels(count);if(count<51)$fatal(1,"long tail failed top clipping %0d",count);
        wait_ms(1300);pixels(count);if(count<34 || count>36)$fatal(1,"2300ms tail remaining %0d",count);
        command(5,0,0,0,0);touch=0;repeat(100)@(negedge clk);
        start_hold(60000);touch=1;wait_ms(2000);pixels(count);if(count<51)$fatal(1,"60000ms tail wrapped %0d",count);
        command(5,0,0,0,0);touch=0;repeat(100)@(negedge clk);
        for(i=0;i<64;i=i+1)if(panel.note_rows[i]!==0)$fatal(1,"STOP left raster pixels");
        $display("PASS tail integration: typed download rejection, 600/2300/60000ms extent/clipping, scroll/shrink/disappear, HOLD score, STOP clears");$finish;
    end
    initial begin #50000000;$fatal(1,"tail integration timeout");end
endmodule
