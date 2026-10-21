`timescale 1ns/1ps
// Reconstruct all 32 PWM planes only from the external HUB75E pins.
module tb_hub75e_status;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,mode16=1,pressure=1,recording=0,ready=1;
    reg [1:0] hold_notes=1;
    reg [15:0] physical=16'h8101,gates=16'h8103;
    reg [7:0] ir=8'h81;
    reg [2:0] timbre=7,analog_mode=4;
    reg [1:0] effect_mode=2;
    reg [3:0] wet=8;
    reg [4:0] volume=8;
    reg [12:0] gain=2048;
    reg [9:0] adc=10'h2a5,position=1023;
    reg analog_valid=1;
    wire r1,g1,b1,r2,g2,b2,a,b,c,d,e,ck,st,oe;
    wire [4:0] panel_row={e,d,c,b,a};
    wire [5:0] rgb={r1,g1,b1,r2,g2,b2};
    hub75e_rhythm_display #(.ENABLE_STATUS(1)) dut(
        .clk(clk),.resetn(resetn),.touch_keys(physical[6:0]),.touch_mode16(mode16),
        .all_touch_keys(gates),.physical_keys(physical),.ir_keys(ir),
        .touch_hold(hold_notes),.pressure_pitch(pressure),.recording(recording),.keys_ready(ready),
        .timbre(timbre),.analog_mode(analog_mode),.effect_mode(effect_mode),.effect_wet(wet),
        .volume(volume),.master_gain(gain),.adc_sample(adc),.analog_position(position),.analog_valid(analog_valid),
        .guide_keys(7'd0),.playing(playing),.ms_tick(1'b0),.note_spawn(1'b0),
        .spawn_keys(7'd0),.spawn_delay_ms(16'd0),.visual_mode(2'd0),
        .reference_ratio(2'd0),.reference_phase(2'd0),.sample_ce(1'b0),
        .mixed_sample(16'sd0),.touch0(16'sd0),.touch1(16'sd0),.sensor_sample(16'sd0),.guitar_sample(16'sd0),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(a),.hub_B(b),.hub_C(c),.hub_D(d),.hub_E(e),.hub_CK(ck),.hub_ST(st),.hub_OE(oe));
    integer red[0:4095],green[0:4095],blue[0:4095];
    reg [5:0] shifted[0:63];
    integer columns=0,latches=0,frames=0,cycles=0,last_latch=0,i,x,y,index,phase;
    time last_rgb=0;
    always @(rgb)last_rgb=$time;
    always @(posedge clk)cycles=cycles+1;
    always @(posedge ck)if(resetn)begin
        if(columns>=64 || st || $time-last_rgb<20)$fatal(1,"RGB/shift setup");
        shifted[columns]=rgb;columns=columns+1;
    end
    always @(posedge st)if(resetn)begin
        if(columns!=64 || !oe || ck || panel_row!==latches%32)$fatal(1,"HUB row/latch/blank");
        if(last_latch && cycles-last_latch!=133)$fatal(1,"Status changed scan timing");
        last_latch=cycles;columns=0;phase=(latches/32)%32;
        if(phase==0 && panel_row==0)for(i=0;i<4096;i=i+1)begin red[i]=0;green[i]=0;blue[i]=0;end
        for(x=0;x<64;x=x+1)begin
            index=panel_row*64+x;
            red[index]=red[index]+shifted[x][5];green[index]=green[index]+shifted[x][4];blue[index]=blue[index]+shifted[x][3];
            index=index+2048;
            red[index]=red[index]+shifted[x][2];green[index]=green[index]+shifted[x][1];blue[index]=blue[index]+shifted[x][0];
        end
        latches=latches+1;if(latches%1024==0)frames=frames+1;
    end
    task check_pixel;
        input integer px,py,pr,pg,pb;
        integer n;
        begin n=py*64+px;
            if(red[n]!==pr || green[n]!==pg || blue[n]!==pb)
                $fatal(1,"Pixel %0d,%0d = %0d,%0d,%0d expected %0d,%0d,%0d",px,py,red[n],green[n],blue[n],pr,pg,pb);
        end
    endtask
    integer output_file;
    task save_frame;
        input [511:0] path;
        begin
            output_file=$fopen(path,"w");if(!output_file)$fatal(1,"preview open failed");
            $fwrite(output_file,"P3\n64 64\n31\n");
            for(y=0;y<64;y=y+1)begin
                for(x=0;x<64;x=x+1)begin index=y*64+x;$fwrite(output_file,"%0d %0d %0d ",red[index],green[index],blue[index]);end
                $fwrite(output_file,"\n");
            end
            $fclose(output_file);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        wait(frames==2);#1;
        check_pixel(0,16,0,26,10); // K1 pressed; first synchronous ROM column.
        check_pixel(8,16,0,20,28); // K2 latched only.
        check_pixel(56,24,0,26,10); // K16 pressed.
        check_pixel(63,24,0,0,0); // Last column separator, no stale data.
        check_pixel(16,10,0,26,10);check_pixel(39,10,0,26,10);
        check_pixel(40,10,1,3,5);check_pixel(63,10,1,3,5); // Exactly half volume.
        check_pixel(16,42,28,16,0);check_pixel(63,42,28,16,0); // Full calibrated range.
        check_pixel(0,56,28,16,0);check_pixel(8,56,4,2,0);check_pixel(56,56,28,16,0); // Independent IR.
        check_pixel(10,33,0,20,28); // Analog mode4 digit (left stem).
        check_pixel(26,33,0,20,28); // ADC high digit2.
        save_frame("sim/build/status16.ppm");
        // Mid-frame changes must wait for the next complete PWM frame.
        repeat(4000)@(negedge clk);
        mode16=0;hold_notes=0;pressure=0;recording=1;ready=0;physical=16'h0080;gates=0;
        timbre=0;analog_mode=1;effect_mode=0;wet=0;volume=0;gain=0;position=0;analog_valid=0;adc=0;
        wait(frames==3);#1;
        check_pixel(56,24,0,26,10);check_pixel(16,10,0,26,10); // No tearing.
        wait(frames==4);#1;
        check_pixel(0,24,0,0,0);check_pixel(56,16,28,16,0); // K9 disabled, K8 pressure.
        check_pixel(16,10,1,3,5);check_pixel(63,10,1,3,5); // Zero volume.
        check_pixel(16,42,31,2,1);check_pixel(63,42,31,2,1); // ADC unavailable.
        check_pixel(59,33,31,2,1); // Alert glyph.
        save_frame("sim/build/status8.ppm");
        playing=1;wait(frames==6);#1;
        check_pixel(6,60,2,3,5); // Automatic return to original guide.
        playing=0;wait(frames==8);#1;
        check_pixel(56,16,28,16,0); // Return to status after stop.
        hold_notes=2;wait(frames==10);#1;
        check_pixel(26,3,28,16,0);
        save_frame("sim/build/status_pedal.ppm");
        $display("PASS HUB status: 32-plane external RGB reconstruction, 8/16 keys, hold, IR, fonts, exact bars, ADC alarm, whole-frame snapshots, guide transition, 133-clock scan");
        $finish;
    end
    initial begin #31000000;$fatal(1,"status timeout");end
endmodule
