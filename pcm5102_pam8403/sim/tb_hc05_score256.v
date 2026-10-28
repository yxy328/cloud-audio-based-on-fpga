`timescale 1ns/1ps
module tb_hc05_score256;
    localparam BIT_TICKS=10;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1;
    wire tx,valid,playing,audition;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(100000),.CONTROL_KEYS(12),.ENABLE_LOOKAHEAD(1)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(playing),.notes_busy(1'b0),.recording(1'b0),.take_recording(1'b0),
        .touch_keys(7'd0),.scan_keys(16'd0),.pressure_mode(1'b0),
        .volume_gain(16'd39321),.pitch_ratio(16'd16384),.toggle_play(1'b0),.restart(1'b0),
        .note_ready(1'b1),.downloaded_valid(valid),.downloaded_playing(playing),.downloaded_audition(audition));
    reg [511:0] incoming=0,last_reply=0;
    reg [7:0] decoded;
    reg [1023:0] line;
    reg [46:0] expected_word;
    integer replies=0,bit_index,i,expected,waited;
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2)@(posedge clk);
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin repeat(BIT_TICKS)@(posedge clk);decoded[bit_index]=tx;end
        repeat(BIT_TICKS)@(posedge clk);if(tx!==1)$fatal(1,"TX stop");
        incoming={incoming[503:0],decoded};
        if(decoded==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task transact;
        input [1023:0] text;input [511:0] reply;
        integer size,k,j;
        begin
            expected=replies+1;size=0;
            for(k=0;k<128;k=k+1)if(text[k*8+:8]!=0)size=k+1;
            for(k=size-1;k>=0;k=k-1)begin
                @(negedge clk);rx=0;repeat(BIT_TICKS)@(negedge clk);
                for(j=0;j<8;j=j+1)begin rx=text[k*8+j];repeat(BIT_TICKS)@(negedge clk);end
                rx=1;repeat(BIT_TICKS)@(negedge clk);
            end
            waited=0;while(replies<expected && waited<20000)begin @(negedge clk);waited=waited+1;end
            if(replies!=expected || last_reply!==reply)$fatal(1,"UART %0s expected %0s got %0s",text,reply,last_reply);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        transact("SONG_BEGIN,257\n",{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_BEGIN,256\n",{"OK",8'd13,8'd10});
        for(i=255;i>=0;i=i-1)begin
            $sformat(line,"SONG_CHORD,%0d,%0d,%0d,%0d\n",i,((i%4+1)<<13)|(1<<(i%12)),100+i,16384+i);
            transact(line,{"OK",8'd13,8'd10});
        end
        transact("SONG_CHORD,256,1,100\n",{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_END\n",{"OK",8'd13,8'd10});
        if(!valid || dut.u_download.active_count!==9'd256)$fatal(1,"UART count256 truncated");
        for(i=0;i<256;i=i+1)begin
            expected_word={i[1:0],(16'd16384+i[15:0]),(13'b1<<(i%12)),(16'd100+i[15:0])};
            if(dut.u_download.score[{dut.u_download.active_bank,i[7:0]}]!==expected_word)$fatal(1,"UART event %0d corrupted",i);
        end
        transact("AUDITION\n",{"OK",8'd13,8'd10});if(!playing || !audition)$fatal(1,"audition not started");
        transact("STOP\n",{"OK",8'd13,8'd10});
        transact("SONG_BEGIN,256\n",{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,1,100\n",{"OK",8'd13,8'd10});
        transact("SONG_END\n",{"ERR,MISSING",8'd13,8'd10});
        if(!valid || dut.u_download.active_count!==9'd256)$fatal(1,"failed UART replacement discarded active song");
        $display("PASS HC05 score256: 3-digit count/index, reverse upload, all256 typed/bent RAM words, upper-bound rejection, audition/STOP, atomic failed replacement (%0d replies)",replies);
        $finish;
    end
    initial begin #100000000;$fatal(1,"UART256 timeout");end
endmodule
