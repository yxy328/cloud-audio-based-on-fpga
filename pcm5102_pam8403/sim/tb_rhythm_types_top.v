`timescale 1ns/1ps
module tb_rhythm_types_top;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [15:0] pads=0;
    wire tx,scl,sdo,bck,lrck,din;
    top #(.CONTROL_KEYS(12),.HC05_BAUD(500000),.GUIDE_LEAD_MS(60),.FSR_ENABLE(0),
        .TOUCH_STARTUP_US(100),.TOUCH_SERIAL_HALF_CYCLES(50),.TOUCH_SERIAL_GAP_CYCLES(500),
        .TOUCH_SERIAL_QUIET_CYCLES(50),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.ir_beam(8'hff),
        .touch_sdo(sdo),.hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl(scl));
    defparam dut.u_keymap.u_download.CLK_HZ=1000000;
    ttp229_model #(.TIMEOUT_NS(5000)) chip(.rst_n(dut.resetn),.scl(scl),.connected(1'b1),.dv(1'b0),.stuck_low(1'b0),.keys(pads),.sdo(sdo));
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24576)) pcm(.bck(bck),.lrck(lrck),.din(din));
    reg [511:0] incoming=0,replies[0:63],message;
    reg [7:0] byte_value;integer reply_count=0,next_reply=0,bit_number;
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin repeat(100)@(posedge clk);byte_value[bit_number]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"UART stop");incoming={incoming[503:0],byte_value};
        if(byte_value==10)begin replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;end
    end
    task send;
        input [511:0] text;input [511:0] expected;
        integer n,j,b,timeout;reg [511:0] tmp;
        begin n=0;tmp=text;while(tmp!=0)begin n=n+1;tmp=tmp>>8;end
            for(j=n-1;j>=0;j=j-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=text[j*8+b];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            timeout=0;while(reply_count<=next_reply && timeout<100000)begin @(negedge clk);timeout=timeout+1;end
            if(reply_count<=next_reply || (expected!=0 && replies[next_reply]!==expected))$fatal(1,"UART %0s: %0s expected %0s",text,replies[next_reply],expected);
            next_reply=next_reply+1;
        end
    endtask
    integer starts=0,ends=0,fd;
    always @(posedge clk)if(dut.resetn)begin
        if(dut.game_event_start)starts=starts+1;if(dut.game_event_end)ends=ends+1;
        if(dut.u_touch_synth.overrun || dut.u_output_mix.clipped)$fatal(1,"audio deadline/headroom");
    end
    initial begin
        wait(dut.touch_ready);repeat(100)@(negedge clk);
        send("VIS,0,228\015","OK\015\012");
        send("SONG_BEGIN,6\015","OK\015\012");
        send("SONG_CHORD,0,1,200\015","OK\015\012");
        send("SONG_CHORD,1,0,200\015","OK\015\012");
        send("SONG_CHORD,2,2048,600\015","OK\015\012");
        send("SONG_CHORD,3,24577,200\015","OK\015\012");
        send("SONG_CHORD,4,32772,300\015","OK\015\012");
        send("SONG_CHORD,5,0,200\015","OK\015\012");send("SONG_END\015","OK\015\012");
        send("PLAY\015","OK\015\012");
        wait(dut.song_guide_keys==1);pads=1;
        wait(dut.u_guide_display.game_score==24'h001000);
        send("VIS,0,240\015","ERR,BUSY\015\012");
        wait(dut.song_guide_keys==0);pads=0;
        wait(dut.song_guide_keys==12'h800);pads=16'h0800;
        wait(dut.u_guide_display.game_holding);pads=16'h0801;
        wait(dut.song_guide_keys==1); // DRAG accepts K1 held during the preceding HOLD.
        wait(dut.u_guide_display.game_score==24'h003500);pads=0;
        wait(dut.song_guide_keys==4);pads=4;
        wait(dut.u_guide_display.game.u_game.matched==4);
        @(negedge clk);pads=8; // Leave the target while sliding onto the next pad.
        wait(dut.u_guide_display.game_score==24'h004500);
        wait(!dut.downloaded_playing);repeat(200)@(negedge clk);pads=0;
        if(starts!=6 || ends!=6 || dut.u_guide_display.game_score!==24'h004500 || dut.u_guide_display.game_combo!==4 || dut.u_guide_display.game_miss!==0)
            $fatal(1,"top events %0d/%0d score=%h combo=%h miss=%h",starts,ends,dut.u_guide_display.game_score,dut.u_guide_display.game_combo,dut.u_guide_display.game_miss);
        send("VIZ?\015",0);fd=$fopen("sim/build/rhythm_types_top_reply.txt","w");$fwrite(fd,"%0s",replies[next_reply-1]);$fclose(fd);
        send("AUDITION\015","OK\015\012");wait(dut.song_guide_keys==1);repeat(100)@(negedge clk);
        if(dut.u_guide_display.game_session)$fatal(1,"audition counted as game");
        send("STOP\015","OK\015\012");
        $display("PASS rhythm_top: UART download/settings/busy/snapshot, real TTP229 K1/K12, tap+hold+preheld DRAG+released-target FLICK=4500, exact onsets, audition exclusion, external I2S");$finish;
    end
    initial begin #100000000;$fatal(1,"top timeout");end
endmodule
