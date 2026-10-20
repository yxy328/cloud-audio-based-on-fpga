`timescale 1ns/1ps
module tb_hc05_audio_record;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1,rec_busy=0,ready=0,overflow=0;
    wire tx,start,stop,abort;
    wire [15:0] session;
    wire mode16,hold;
    wire [2:0] analog_mode;
    integer starts=0,stops=0,aborts=0,replies=0,b;
    reg [255:0] incoming=0,last_reply=0;
    reg [7:0] data;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(1'b0),.notes_busy(1'b0),.recording(1'b0),
        .touch_keys(7'd0),.pressure_mode(1'b0),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .audio_rec_busy(rec_busy),.audio_rec_ready(ready),.audio_rec_overflow(overflow),
        .audio_rec_start(start),.audio_rec_stop(stop),.audio_rec_abort(abort),.audio_rec_session(session),
        .touch_mode16(mode16),.touch_hold(hold),.analog_mode(analog_mode),.adc_sample(10'd0),.adc_timeout(1'b0));
    always @(negedge clk)begin
        if(start)starts=starts+1;if(stop)stops=stops+1;if(abort)aborts=aborts+1;
    end
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        if(tx!==0)$fatal(1,"TX start");
        for(b=0;b<8;b=b+1)begin repeat(100)@(posedge clk);data[b]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"TX stop");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task command;
        input [255:0] message;
        input integer length;
        input [255:0] expected;
        integer c,bitno,target;
        begin
            target=replies+1;
            for(c=length-1;c>=0;c=c-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(bitno=0;bitno<8;bitno=bitno+1)begin rx=message[c*8+bitno];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            wait(replies==target);
            if(last_reply!==expected)$fatal(1,"Command %0s expected %0s got %0s",message,expected,last_reply);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        command("AREC?\n",6,{"AREC,0,0,0",8'd13,8'd10});
        command("AREC_START,1\n",13,{"ERR,STATE",8'd13,8'd10});
        ready=1;
        command("AREC_START,65535\n",17,{"OK",8'd13,8'd10});
        if(starts!=1 || session!=65535)$fatal(1,"Session/pulse");
        rec_busy=1;overflow=1;
        command("AREC?\n",6,{"AREC,1,1,1",8'd13,8'd10});
        command("AREC_START,0\n",13,{"ERR,BUSY",8'd13,8'd10});
        command("AREC_STOP\n",10,{"OK",8'd13,8'd10});
        command("AREC_ABORT\n",11,{"OK",8'd13,8'd10});
        if(starts!=1 || stops!=1 || aborts!=1 || session!=65535)$fatal(1,"Busy or pulse");
        rec_busy=0;overflow=0;
        command("AREC_START,65536\n",17,{"ERR,RANGE",8'd13,8'd10});
        command("AREC_START,-1\n",14,{"ERR,CMD",8'd13,8'd10});
        command("AREC_START,x\n",13,{"ERR,CMD",8'd13,8'd10});
        command("AREC_START,1,2\n",15,{"ERR,CMD",8'd13,8'd10});
        command("AREC_START,\n",12,{"ERR,CMD",8'd13,8'd10});
        if(starts!=1 || session!=65535)$fatal(1,"Invalid command committed");
        command("TOUCH,16\n",9,{"OK",8'd13,8'd10});
        command("HOLD,1\n",7,{"OK",8'd13,8'd10});
        command("ANALOG,4\n",9,{"OK",8'd13,8'd10});
        command("AREC_START,0\n",13,{"OK",8'd13,8'd10});
        if(!mode16 || !hold || analog_mode!=4 || starts!=2 || session!=0)$fatal(1,"Live controls blocked audio capture");
        command("REC_START\n",10,{"ERR,BUSY",8'd13,8'd10});
        command("PCM,1\n",6,{"ERR,CMD",8'd13,8'd10});
        command("AREC_STOP\n",10,{"OK",8'd13,8'd10});
        command("AREC_ABORT\n",11,{"OK",8'd13,8'd10});
        command("PING\n",5,{"PONG",8'd13,8'd10});
        if(stops!=2 || aborts!=2)$fatal(1,"Idle stop/abort");
        $display("PASS audio control: %0d real UART transactions, strict session/range, busy/CTS/status, pulse counts, 16-key/hold/analog coexistence, legacy event log guards, no PCM command",replies);$finish;
    end
    initial begin #30000000;$fatal(1,"Audio control timeout");end
endmodule
