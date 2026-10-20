`timescale 1ns/1ps
module tb_hc05_take;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1;wire tx;wire [2:0] take_command;
    reg [7:0] take_flags=0;reg [3:0] take_error=0;
    reg [23:0] take_elapsed=24'h123456,take_duration=24'h010203;
    reg [10:0] take_count=11'd1024;
    hc05_keymap #(.CLK_HZ(100000),.BAUD(10000),.ENABLE_EVENT_TAKE(1)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),.song_busy(1'b0),
        .notes_busy(1'b0),.recording(1'b0),.touch_keys(7'd0),.pressure_mode(1'b0),
        .volume_gain(16'hffff),.pitch_ratio(16'hffff),.toggle_play(1'b0),.restart(1'b0),
        .note_ready(1'b1),.adc_sample(10'd0),.adc_timeout(1'b0),
        .audio_rec_busy(1'b0),.audio_rec_ready(1'b0),.audio_rec_overflow(1'b0),
        .take_command(take_command),.take_flags(take_flags),.take_error(take_error),
        .take_elapsed(take_elapsed),.take_duration(take_duration),.take_count(take_count));
    integer replies=0,bitno,pulses=0,checks=0;
    reg [2:0] last_command=0;reg [255:0] incoming=0,last_reply=0;reg [7:0] data;
    always @(negedge clk)if(take_command!=0)begin pulses=pulses+1;last_command=take_command;end
    initial forever begin
        @(negedge tx);repeat(5)@(posedge clk);
        for(bitno=0;bitno<8;bitno=bitno+1)begin repeat(10)@(posedge clk);data[bitno]=tx;end
        repeat(10)@(posedge clk);if(tx!==1)$fatal(1,"UART stop");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task transact;
        input [255:0] message;input integer length;input [255:0] expected;input [2:0] cmd;
        integer c,k,target,old_pulses;begin target=replies+1;old_pulses=pulses;
            for(c=length-1;c>=0;c=c-1)begin
                @(negedge clk);rx=0;repeat(10)@(negedge clk);
                for(k=0;k<8;k=k+1)begin rx=message[c*8+k];repeat(10)@(negedge clk);end
                rx=1;repeat(10)@(negedge clk);
            end
            wait(replies==target);repeat(2)@(negedge clk);checks=checks+1;
            if(last_reply!==expected || pulses-old_pulses!=(cmd==0 ? 0 : 1) || (cmd!=0 && last_command!=cmd))
                $fatal(1,"Command %0s reply '%0s', pulses=%0d command=%0d",message,last_reply,pulses-old_pulses,last_command);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        transact("TAKE?\n",6,{"TAKE,00,0,123456,400,010203",8'd13,8'd10},0);
        transact("TAKE_REC\n",9,{"OK",8'd13,8'd10},1);
        take_flags=1;transact("TAKE_PLAY\n",10,{"ERR,BUSY",8'd13,8'd10},0);
        transact("TAKE_STOP\n",10,{"OK",8'd13,8'd10},2);
        take_flags=0;transact("TAKE_PLAY\n",10,{"OK",8'd13,8'd10},3);
        transact("TAKE_SAVE\n",10,{"OK",8'd13,8'd10},7);
        transact("TAKE_DEL\n",9,{"OK",8'd13,8'd10},4);
        take_flags=8'h40;transact("TAKE_YES\n",9,{"OK",8'd13,8'd10},5);
        transact("TAKE_NO\n",8,{"OK",8'd13,8'd10},6);
        take_flags=8'h20;transact("TAKE_DEL\n",9,{"ERR,BUSY",8'd13,8'd10},0);
        take_flags=8'h4c;take_error=8;
        transact("TAKE?\n",6,{"TAKE,4C,8,123456,400,010203",8'd13,8'd10},0);
        transact("TAKE_PLAY,1\n",12,{"ERR,CMD",8'd13,8'd10},0);
        transact("REC_START\n",10,{"ERR,STATE",8'd13,8'd10},0);
        $display("PASS tb_hc05_take: %0d bit-level UART transactions",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"UART take timeout");end
endmodule
