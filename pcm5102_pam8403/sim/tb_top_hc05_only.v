`timescale 1ns/1ps
// Default HC-05-only elaboration: real 50MHz/I2S, accelerated control baud.
module tb_top_hc05_only;
    reg clk=0;always #10 clk=~clk;
    reg rx=1,cts=0;
    reg [7:0] pads=0;
    wire tx,unused_usb_tx,bck,lrck,din,hck,lat,oe;
    tri1 scl,sda;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16),
        .FSR_ENABLE(0),.IR_FILTER_CYCLES(100),.GUITAR_STRING_LENGTH(16)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.touch_sdo(1'b1),
        .ir_beam(8'd0),.hc05_rx(rx),.hc05_tx(tx),
        .audio_rec_cts_n(cts),.audio_rec_tx(unused_usb_tx),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.scl(scl),.sda(sda),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe));
    i2s_pcm_monitor #(.CAPTURE_FILE("sim/build/hc05_only_i2s.csv")) monitor(
        .bck(bck),.lrck(lrck),.din(din),.resetn(dut.resetn));
    integer columns=0,latches=0,nonzero=0,i;
    always @(posedge hck)if(dut.resetn)columns=columns+1;
    always @(posedge lat)if(dut.resetn)begin
        if(columns!=64 || oe!==1)$fatal(1,"HC05-only HUB75 scan failed");
        columns=0;latches=latches+1;
    end
    always @(posedge clk)if(dut.resetn)begin
        if(unused_usb_tx!==1 || dut.audio_rec_busy!==0 || dut.audio_rec_ready!==0 || dut.audio_rec_overflow!==0)
            $fatal(1,"disabled USB recorder was active");
        if(dut.u_touch_synth.overrun || dut.sensor_overrun)$fatal(1,"HC05-only audio deadline");
    end
    integer replies=0,bitno;
    reg [255:0] incoming=0,last_reply=0;
    reg [7:0] data;
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        for(bitno=0;bitno<8;bitno=bitno+1)begin repeat(100)@(posedge clk);data[bitno]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"HC05 stop bit");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task command;
        input [255:0] text;input integer length;input [255:0] expected;
        integer n,b,target;
        begin
            target=replies+1;
            for(n=length-1;n>=0;n=n-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[n*8+b];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            wait(replies==target);@(negedge clk);
            if(last_reply!==expected)$fatal(1,"HC05-only '%0s' got '%0s'",text,last_reply);
        end
    endtask
    initial begin
        wait(dut.touch_ready);repeat(3)@(negedge clk);
        command("PING\n",5,{"PONG",8'd13,8'd10});
        command("AREC?\n",6,{"AREC,0,0,0",8'd13,8'd10});
        command("AREC_START,1\n",13,{"ERR,STATE",8'd13,8'd10});
        command("AREC_STOP\n",10,{"OK",8'd13,8'd10});
        command("AREC_ABORT\n",11,{"OK",8'd13,8'd10});
        command("MAP,1,64\n",9,{"OK,MAP,1,64",8'd13,8'd10});
        command("VOLUME,16\n",10,{"OK",8'd13,8'd10});
        pads=1;repeat(120)@(posedge lrck);
        for(i=monitor.pcm_count-40;i<monitor.pcm_count;i=i+1)
            if(monitor.pcm[i]!=0)nonzero=nonzero+1;
        if(nonzero<20)$fatal(1,"HC05-only physical touch did not produce audio");
        command("VIS,3\n",6,{"OK",8'd13,8'd10});
        repeat(1000)begin @(negedge clk);cts=~cts;end
        command("AREC_START,65535\n",17,{"ERR,STATE",8'd13,8'd10});
        pads=0;repeat(140)@(posedge lrck);
        for(i=monitor.pcm_count-20;i<monitor.pcm_count;i=i+1)
            if(monitor.pcm[i]!==0)$fatal(1,"HC05-only touch release did not mute");
        if(latches<100)$fatal(1,"insufficient HC05-only panel coverage");
        $display("PASS HC05-only top: UART controls/map/page, unavailable USB record status/rejection, CTS isolation, physical touch/I2S/release, TDM and HUB75");
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #50000000;$fatal(1,"HC05-only top timeout");end
endmodule
