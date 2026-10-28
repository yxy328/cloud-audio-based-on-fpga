`timescale 1ns/1ps
module tb_rhythm_panel;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,ms_tick=0,note_spawn=0,event_start=0,event_end=0,spawn_long=0;
    reg [11:0] touch_keys=0,guide_keys=0,spawn_keys=0;
    reg [15:0] duration=200;
    reg [1:0] spawn_type=0;reg spawn_body=0;reg [15:0] spawn_delay=1250;
    reg [7:0] settings=8'he4;
    wire r1,g1,b1,r2,g2,b2,a,b,c,d,e,ck,lat,oe;
    wire ready;
    wire [111:0] snapshot;
    hub75e_rhythm_display #(.CONTROL_KEYS(12),.ENABLE_GAME(1)) dut(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),.touch_keys(touch_keys),
        .guide_keys(guide_keys),.note_spawn(note_spawn),.spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay),
        .game_spawn_long(spawn_long),.game_event_start(event_start),.game_event_end(event_end),
        .game_spawn_type(spawn_type),.game_spawn_body(spawn_body),
        .game_event_type(duration>=500 ? 2'd1 : 2'd0),.game_gesture(1'b0),
        .game_event_duration(duration),.game_settings(settings),.touch_mode16(1'b1),.all_touch_keys({4'd0,touch_keys}),
        .note_ready(ready),.visual_mode(2'd0),.visual_snapshot(snapshot),.hub_R1(r1),.hub_G1(g1),.hub_B1(b1),
        .hub_R2(r2),.hub_G2(g2),.hub_B2(b2),.hub_A(a),.hub_B(b),.hub_C(c),.hub_D(d),.hub_E(e),
        .hub_CK(ck),.hub_ST(lat),.hub_OE(oe));
    integer columns=0,rows=0,cycles=0,last_latch=0;
    integer reds[0:4095],greens[0:4095],blues[0:4095];
    reg [5:0] line[0:63];reg capture=0;
    integer row,x,i,fd,fixture;
    time rgb_changed=0;
    always @({r1,g1,b1,r2,g2,b2})rgb_changed=$time;
    always @(posedge clk)cycles=cycles+1;
    always @(posedge ck)if(resetn)begin
        if(columns>=64 || $time-rgb_changed<20)$fatal(1,"scan RGB/column setup");
        line[columns]={r1,g1,b1,r2,g2,b2};columns=columns+1;
    end
    always @(posedge lat)if(resetn)begin
        if(columns!=64 || !oe || ck)$fatal(1,"scan latch/blank");
        if(last_latch!=0 && cycles-last_latch!=133)$fatal(1,"scan row period changed");
        last_latch=cycles;columns=0;
        if(capture)begin
            row={e,d,c,b,a};
            for(x=0;x<64;x=x+1)begin
                reds[row*64+x]=reds[row*64+x]+line[x][5];
                greens[row*64+x]=greens[row*64+x]+line[x][4];
                blues[row*64+x]=blues[row*64+x]+line[x][3];
                reds[(row+32)*64+x]=reds[(row+32)*64+x]+line[x][2];
                greens[(row+32)*64+x]=greens[(row+32)*64+x]+line[x][1];
                blues[(row+32)*64+x]=blues[(row+32)*64+x]+line[x][0];
            end
            rows=rows+1;
        end
    end
    task head;
        input [11:0] keys;input long;
        begin wait(ready);@(negedge clk);spawn_keys=keys;spawn_long=long;spawn_type=long;note_spawn=1;
            @(negedge clk);note_spawn=0;repeat(5)@(negedge clk);end
    endtask
    task staircase;
        input integer key_index,head_y;
        integer sx,sy;
        begin
            for(sy=head_y-1;sy<=head_y;sy=sy+1)
                for(sx=0;sx<5;sx=sx+1)begin
                    if((sy==head_y-1 && sx>=2) || (sy==head_y && sx<=2))pixel(key_index*5+sx,sy,31,4,24);
                    else if(sy==54)pixel(key_index*5+sx,sy,8,8,8);
                    else if(sx==0)pixel(key_index*5+sx,sy,2,3,5);
                    else pixel(key_index*5+sx,sy,1,1,2);
                end
        end
    endtask
    task collect_frame;
        begin
            capture=0;
            wait(dut.pwm_phase==31 && {e,d,c,b,a}==31 && lat);@(negedge lat);
            for(i=0;i<4096;i=i+1)begin reds[i]=0;greens[i]=0;blues[i]=0;end
            rows=0;capture=1;
            wait(rows==1024);@(negedge lat);capture=0;
        end
    endtask
    task typed_pixel;
        input [11:0] keys;input [1:0] kind;input body;input [15:0] delay;
        begin wait(ready);@(negedge clk);spawn_keys=keys;spawn_type=kind;spawn_body=body;spawn_delay=delay;note_spawn=1;
            @(negedge clk);note_spawn=0;repeat(5)@(negedge clk);end
    endtask
    task target;
        input [11:0] keys;input [15:0] length;
        begin @(negedge clk);guide_keys=keys;duration=length;event_start=1;
            @(negedge clk);event_start=0;repeat(40)@(negedge clk);end
    endtask
    task pixel;
        input integer px,py,r,g,b;
        begin i=py*64+px;
            if(reds[i]!=r || greens[i]!=g || blues[i]!=b)
                $fatal(1,"external pixel %0d/%0d got %0d/%0d/%0d expected %0d/%0d/%0d",px,py,reds[i],greens[i],blues[i],r,g,b);
        end
    endtask
    integer tail_delay,key_number,dx;
    initial begin
        for(i=0;i<4096;i=i+1)begin reds[i]=0;greens[i]=0;blues[i]=0;end
        repeat(4)@(negedge clk);resetn=1;playing=1;repeat(40)@(negedge clk);
        head(1,0);head(4,1);target(1,200);
        touch_keys=1;repeat(40)@(negedge clk);
        if(dut.game_score!=24'h001000)$fatal(1,"tap did not score");
        touch_keys=0;target(4,600);touch_keys=4;repeat(80)@(negedge clk);
        if(!dut.game_holding)$fatal(1,"long not acquired");
        typed_pixel(12'h010,1,0,600);
        for(tail_delay=630;tail_delay<1200;tail_delay=tail_delay+28)typed_pixel(12'h010,1,1,tail_delay);
        typed_pixel(12'h080,2,0,900);typed_pixel(12'h400,3,0,1300);
        typed_pixel(12'h800,0,0,1100);
        typed_pixel(12'h008,3,0,650); // head32, cap31 crosses upper/lower scan ports
        typed_pixel(12'h800,3,0,0);   // lower row anchored to the judgment line
        wait(dut.pwm_phase==31 && {e,d,c,b,a}==31 && lat);@(negedge lat);capture=1;
        // Both legacy values of the old width bit must render exactly 5px.
        wait(rows==512);@(negedge lat);settings[4]=1;
        wait(rows==1024);@(negedge lat);capture=0;settings[4]=0;
        repeat(2)@(negedge clk); // Let the telemetry settings field settle.
        // Check every pixel of five-wide heads, including the last lane.
        for(dx=0;dx<5;dx=dx+1)begin
            pixel(dx,11,0,24,31);pixel(10+dx,11,31,25,0);
            pixel(20+dx,34,0,24,31);pixel(20+dx,20,0,10,24);
            pixel(35+dx,23,31,25,0);
            pixel(55+dx,16,0,24,31);
        end
        staircase(10,9);staircase(3,32);staircase(11,54);
        pixel(52,10,1,1,2);pixel(51,7,0,0,0); // exactly two rows, no wrapping into HUD
        pixel(5,11,2,3,5);pixel(1,12,1,1,2); // exact width/height boundaries
        pixel(10,54,31,25,0);pixel(1,50,22,22,0);
        pixel(40,1,31,3,0);pixel(9,1,31,20,0); // score/ combo on one top row
        pixel(60,62,0,0,0); // K13..K16 indicators removed from the game page
        for(key_number=0;key_number<12;key_number=key_number+1)
            for(dx=0;dx<5;dx=dx+1)begin
                if(key_number==2)pixel(key_number*5+dx,62,31,25,0);
                else pixel(key_number*5+dx,62,0,key_number%2 ? 5 : 8,key_number%2 ? 14 : 22);
            end
        fd=$fopen("sim/build/rhythm_panel.ppm","w");$fwrite(fd,"P3\n64 64\n31\n");
        for(i=0;i<4096;i=i+1)$fwrite(fd,"%0d %0d %0d\n",reds[i],greens[i],blues[i]);$fclose(fd);
        fixture=$fopen("sim/build/rhythm_snapshot.txt","w");$fwrite(fixture,"V,%028h\n",snapshot);$fclose(fixture);
        // One actual raster scroll moves both halves of the cap together.
        for(tail_delay=0;tail_delay<29;tail_delay=tail_delay+1)begin
            @(negedge clk);ms_tick=1;@(negedge clk);ms_tick=0;repeat(14)@(negedge clk);
        end
        collect_frame;
        staircase(10,10);staircase(3,33);
        pixel(52,8,1,1,2);pixel(55,54,8,8,8);pixel(57,53,1,1,2); // old pixels clear, hit head leaves at54
        @(negedge clk);playing=0;repeat(8)@(negedge clk);playing=1;wait(ready);
        collect_frame;
        pixel(52,9,1,1,2);pixel(15,33,2,3,5);pixel(57,54,8,8,8);
        $display("PASS rhythm_panel: external RGB5/PWM, 5x2 stepped FLICK ..###/###.., scan boundary31/32, line54, scrolling and STOP clear, exact5px TAP/HOLD/DRAG and12keys, red score, 133-clock rows");$finish;
    end
    initial begin #100000000;$fatal(1,"panel timeout");end
endmodule
