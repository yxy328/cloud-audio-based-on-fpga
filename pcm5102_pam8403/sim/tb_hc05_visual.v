`timescale 1ns/1ps
module tb_hc05_visual;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1,button=0,ce=0;
    wire tx,visual_write,xy_write,restart;
    wire [1:0] remote_mode,mode,ratio,phase,xy_ratio,xy_phase;
    reg [111:0] snapshot=112'h17E78440F7358B52507314831040;
    integer replies=0,writes=0,b,c,n,fixture;
    reg [255:0] incoming=0,last_reply=0;
    reg [7:0] data,ch;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(1'b1),.notes_busy(1'b1),.recording(1'b1),
        .touch_keys(7'd0),.pressure_mode(1'b0),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .visual_write(visual_write),.remote_mode(remote_mode),.visual_requested(mode),
        .reference_ratio(ratio),.reference_phase(phase),.visual_snapshot(snapshot),
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase));
    display_mode_control #(.HOLD_FRAMES(4)) control(
        .clk(clk),.resetn(resetn),.frame_ce(ce),.button_level(button),
        .visual_write(visual_write),.remote_mode(remote_mode),
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase),
        .restart(restart),.visual_mode(mode),.reference_ratio(ratio),.reference_phase(phase));
    always @(negedge clk)if(visual_write)writes=writes+1;
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        if(tx!==0)$fatal(1,"TX start");
        for(b=0;b<8;b=b+1)begin repeat(100)@(posedge clk);data[b]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"TX stop");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task command;
        input [255:0] message;input integer length;input [255:0] expected;
        integer byte_index,bitno,target;
        begin
            target=replies+1;
            for(byte_index=length-1;byte_index>=0;byte_index=byte_index-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(bitno=0;bitno<8;bitno=bitno+1)begin rx=message[byte_index*8+bitno];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            wait(replies==target);@(negedge clk);
            if(last_reply!==expected)$fatal(1,"Reply expected %0s got %0s",expected,last_reply);
        end
    endtask
    initial begin
        fixture=$fopen("sim/build/led_visual_protocol.txt","wb");
        repeat(5)@(negedge clk);resetn=1;
        for(n=0;n<4;n=n+1)begin
            ch=48+n;command({"VIS,",ch,8'd10},6,{"OK",8'd13,8'd10});
            if(mode!==n[1:0] || writes!=n+1)$fatal(1,"Remote page pulse or payload");
        end
        command("VIS?\n",5,{"VIS,3,3,2,0,2,1,7",8'd13,8'd10});
        $fwrite(fixture,"%0s",last_reply);
        // Changes while the 32-byte response is sent cannot tear its snapshot.
        fork
            command("VIZ?\n",5,{"V,17E78440F7358B52507314831040",8'd13,8'd10});
            begin wait(dut.visual_reply && dut.state==2);@(negedge clk);snapshot=0;end
        join
        $fwrite(fixture,"%0s",last_reply);
        snapshot=112'h1000000000000000000000000000;
        command("VIZ?\n",5,{"V,1000000000000000000000000000",8'd13,8'd10});
        $fwrite(fixture,"%0s",last_reply);
        command("VIS,4\n",6,{"ERR,RANGE",8'd13,8'd10});
        command("VIS,x\n",6,{"ERR,RANGE",8'd13,8'd10});
        command("VIS,01\n",7,{"ERR,CMD",8'd13,8'd10});
        command("VIS,\n",5,{"ERR,CMD",8'd13,8'd10});
        command("VIS;1\n",6,{"ERR,CMD",8'd13,8'd10});
        command("VIZ?,1\n",7,{"ERR,CMD",8'd13,8'd10});
        if(writes!=4 || mode!=3)$fatal(1,"Rejected command changed display");
        command("XY,1,2\n",7,{"OK",8'd13,8'd10});
        command("PING\n",5,{"PONG",8'd13,8'd10});
        if(ratio!=1 || phase!=2)$fatal(1,"Legacy XY failed after telemetry");
        $fclose(fixture);
        $display("PASS visual UART: four pages, requested/active state, 32-byte atomic snapshots, strict errors, XY/PING coexistence");$finish;
    end
    initial begin #20000000;$fatal(1,"Visual UART timeout");end
endmodule
