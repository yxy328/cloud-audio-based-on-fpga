`timescale 1ns/1ps
module tb_top_take;
`ifdef AUDIO_QUICK_SIM
    localparam PAD_HALF=50,PAD_GAP=2500,PAD_QUIET=100,PAD_TIMEOUT=40000;
    localparam CAPTURE="sim/build/take_i2s_quick.csv";
`else
    localparam PAD_HALF=500,PAD_GAP=125000,PAD_QUIET=1000,PAD_TIMEOUT=2000000;
    localparam CAPTURE="sim/build/take_i2s.csv";
`endif
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [15:0] keys=0;reg [7:0] ir=0;
    wire tx,bck,lrck,din,tscl,sdo,cs_n,sck,mosi,miso,hck,lat,oe;
    tri1 scl,sda;
    top #(.ENABLE_EVENT_TAKE(1),.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),
        .TOUCH_SERIAL_HALF_CYCLES(PAD_HALF),.TOUCH_SERIAL_GAP_CYCLES(PAD_GAP),.TOUCH_SERIAL_QUIET_CYCLES(PAD_QUIET),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16),
        .FSR_ENABLE(0),.IR_FILTER_CYCLES(100),.GUITAR_STRING_LENGTH(16)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.touch_sdo(sdo),.touch_scl(tscl),
        .ir_beam(ir),.hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(1'b1),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.scl(scl),.sda(sda),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe),
        .flash_cs_n(cs_n),.flash_sck(sck),.flash_mosi(mosi),.flash_miso(miso));
`ifdef AUDIO_QUICK_SIM
    // Shorten peripheral waits while preserving the 50MHz/1024 audio schedule.
    defparam dut.take_enabled.u_store.HALF_CYCLES=3;
`endif
    ttp229_model #(.TIMEOUT_NS(PAD_TIMEOUT)) chip(.rst_n(dut.resetn),.scl(tscl),.connected(1'b1),.dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(sdo));
    take_nor_model flash(.*);
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767),.SUPPORT_RESET(1),.CAPTURE_FILE(CAPTURE)) monitor(
        .bck(bck),.lrck(lrck),.din(din),.resetn(dut.resetn));
    integer replies=0,b,frames=0,columns=0,latches=0,checks=0,nonzero=0;
    reg [255:0] incoming=0,last_reply=0;reg [7:0] data;
    always @(posedge hck)if(dut.resetn)columns=columns+1;
    always @(posedge lat)if(dut.resetn)begin
        if(columns!=64 || oe!==1)$fatal(1,"HUB75 scan stalled");
        columns=0;latches=latches+1;
    end
    always @(posedge clk)if(dut.resetn && dut.frame_ce)begin
        frames=frames+1;
        if(dut.u_touch_synth.overrun || dut.sensor_overrun)$fatal(1,"Audio deadline missed");
        if(dut.perf_playing && dut.audio_sample!=0)nonzero=nonzero+1;
    end
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        for(b=0;b<8;b=b+1)begin repeat(100)@(posedge clk);data[b]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"UART stop bit");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task check;input condition;input [255:0] message;begin
        checks=checks+1;if(!condition)$fatal(1,"%0s perf_error=%0d",message,dut.perf_error);
    end endtask
    task command;input [255:0] message;input integer length;
        integer c,k,target;begin target=replies+1;
            for(c=length-1;c>=0;c=c-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(k=0;k<8;k=k+1)begin rx=message[c*8+k];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            wait(replies==target);
            if(last_reply!=={"OK",8'd13,8'd10})$fatal(1,"Command %0s got %0s",message,last_reply);
        end
    endtask
    task wait_frames;input integer n;integer target;begin target=frames+n;wait(frames>=target);@(negedge clk);end endtask
    task press;input [15:0] mask;begin
        keys=mask;wait(dut.touch_keys==mask);wait_frames(3);
        keys=0;wait(dut.touch_keys==0);wait_frames(3);
    end endtask
    integer saved_count,save_audio_frames=0;
    reg replayed_volume=0,replayed_timbre=0;
    always @(posedge clk)if(dut.resetn && dut.frame_ce)begin
        if(dut.perf_replay && dut.u_master_volume.target_gain==2048)replayed_volume=1;
        if(dut.perf_replay && dut.u_gesture.control_timbre==7 && dut.u_gesture.control_bank && dut.u_gesture.control_vibrato)replayed_timbre=1;
        if(dut.nv_busy && dut.audio_sample!=0)save_audio_frames=save_audio_frames+1;
    end
    time key_start;
    initial begin
        wait(dut.nv_boot_done);wait(dut.touch_ready);wait_frames(3);
        $display("top take stage: boot complete");
        check(dut.touch_mode16 && !dut.perf_available,"default serial / empty NOR");
        press(16'h4000);check(dut.perf_recording,"K15 standalone record start");
        key_start=$time;keys=1;wait(dut.touch_active[0]);wait(monitor.last_pcm!=0);
        check($time-key_start<=10000000,"touch-to-I2S <=10ms");
        wait_frames(20);keys=16'h0885;wait(dut.touch_keys==16'h0885);wait_frames(20);
        command("VOLUME,8\n",9);command("TONE,7\n",7);command("BANK,1\n",7);command("VIBRATO,1\n",10);
        ir=3;wait_frames(20);
        command("GUITAR\n",7);wait_frames(100);
        keys=0;ir=0;wait(dut.touch_keys==0);wait_frames(30);
        press(16'h2000);wait(!dut.perf_recording);
        check(!dut.perf_saved && dut.perf_available && flash.wren_count==0,"K14 STOP retains RAM without Flash writes");
        saved_count=dut.perf_count;check(saved_count>40 && saved_count<1024,"event count");
        $display("top take stage: stopped %0d RAM events",saved_count);
        command("PANIC\n",6);wait_frames(10);
        keys=16'h1000;wait(dut.perf_playing);keys=0;
        wait(dut.perf_replay);@(negedge clk);
        check(dut.u_master_volume.target_gain==4096 && dut.u_touch_synth.low_steps[31:0]==23012828,
            "initial recorded volume and C4 pitch restored");
        wait(dut.touch_note_gates==16'h0885);
        check(dut.u_master_volume.target_gain<=4096,"playback gain range");
        wait(!dut.perf_playing);wait_frames(12);
        check(dut.touch_active==0 && dut.sensor_voice_count==0 && monitor.last_pcm==0,"hard end clears all tails");
        check(nonzero>100 && latches>64,"replayed audio and panel scan");
        check(replayed_volume,"recorded volume change applied during playback");
        check(replayed_timbre,"recorded timbre, octave bank and vibrato restored");
        check(!dut.perf_saved && flash.wren_count==0,"RAM replay before SAVE");
        keys=16'h8001;wait(dut.touch_keys==16'h8001);wait(dut.nv_busy);keys=16'h0001;
        wait(dut.perf_saved || dut.perf_error!=0);
        check(dut.perf_saved && dut.perf_available && !dut.perf_full,"K16 NOR saved and verified");
        check(save_audio_frames>20,"live audio continues during Flash saving");
        keys=0;wait(dut.touch_keys==0);wait_frames(20);
        $display("top take stage: RAM playback and separate SAVE passed");
        // Simulated power cycle: reset FPGA state, retain NOR model only.
        keys=0;ir=0;force dut.power_count=0;repeat(8)@(negedge clk);release dut.power_count;
        columns=0;wait(dut.nv_boot_done);wait(dut.touch_ready);wait_frames(4);
        check(dut.perf_saved && dut.perf_count==saved_count,"NOR boot recovery without phone");
        keys=16'h1000;wait(dut.perf_playing);keys=0;
        wait(dut.touch_note_gates!=0);
        keys=16'h2000;wait(!dut.perf_playing);keys=0;wait_frames(12);
        check(dut.touch_active==0 && dut.sensor_voice_count==0 && monitor.last_pcm==0,"K14 offline stop clears voices");
        $display("PASS tb_top_take: %0d checks, %0d events, %0d replayed nonzero I2S frames; no hardware tested",checks,saved_count,nonzero);$finish;
    end
    initial begin #500000000;$fatal(1,"Top take timeout rec=%b play=%b error=%d",dut.perf_recording,dut.perf_playing,dut.perf_error);end
endmodule
