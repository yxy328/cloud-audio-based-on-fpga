`timescale 1ns/1ps
module tb_hc05_xy;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1;
    wire tx,write;
    wire [1:0] ratio,phase;
    integer writes=0,replies=0,b,r,p,n;
    reg [255:0] incoming=0,last_reply=0;
    reg [7:0] data;
    reg [7:0] rchar,pchar;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(1'b1),.notes_busy(1'b1),.recording(1'b1),
        .touch_keys(7'd1),.pressure_mode(1'b0),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .xy_write(write),.xy_ratio(ratio),.xy_phase(phase));
    always @(negedge clk)if(write)writes=writes+1;
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
            if(last_reply!==expected)$fatal(1,"Reply expected %0s got %0s",expected,last_reply);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        for(r=0;r<4;r=r+1)for(p=0;p<4;p=p+1)begin
            rchar=48+r;pchar=48+p;
            command({"XY,",rchar,",",pchar,8'd10},7,{"OK",8'd13,8'd10});
            if(ratio!==r[1:0] || phase!==p[1:0] || writes!=r*4+p+1)$fatal(1,"XY update/payload/pulse");
        end
        command("XY,4,0\n",7,{"ERR,RANGE",8'd13,8'd10});
        command("XY,1,4\n",7,{"ERR,RANGE",8'd13,8'd10});
        command("XY,1,x\n",7,{"ERR,RANGE",8'd13,8'd10});
        command("XY,1,\n",6,{"ERR,CMD",8'd13,8'd10});
        command("XY,01,0\n",8,{"ERR,CMD",8'd13,8'd10});
        command("XY,1,0,0\n",9,{"ERR,CMD",8'd13,8'd10});
        command("XY,1;0\n",7,{"ERR,CMD",8'd13,8'd10});
        if(writes!=16 || ratio!=3 || phase!=3)$fatal(1,"Invalid command changed XY");
        command("PING\n",5,{"PONG",8'd13,8'd10});
        $display("PASS UART XY: all 16 settings, strict syntax/range, atomic rejection, one write/command, available while playing, PING coexistence");$finish;
    end
    initial begin #20000000;$fatal(1,"UART XY timeout");end
endmodule
