`timescale 1ns/1ps
module tb_rhythm_protocol;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1,dashboard=0;wire tx;wire [95:0] note_map;
    wire bend_write;wire [3:0] bend_index;wire [15:0] bend_ratio;
    hc05_keymap #(.CONTROL_KEYS(12),.BAUD(1000000),.ENABLE_EVENT_TAKE(1),.ENABLE_DOWNLOADED_INCREMENT(0)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.note_map(note_map),.keys_ready(1'b1),
        .song_busy(1'b0),.notes_busy(1'b0),.recording(1'b0),.touch_keys(7'd0),.scan_keys(16'd0),
        .pressure_mode(1'b0),.volume_gain(16'hffff),.pitch_ratio(16'hffff),.toggle_play(1'b0),.restart(1'b0),
        .note_ready(1'b1),.bend_write(bend_write),.bend_index(bend_index),.bend_ratio(bend_ratio),
        .visual_snapshot({4'd2,76'd0,dashboard,31'd0}),.visual_requested(2'd0),.reference_ratio(2'd0),.reference_phase(2'd0),.take_recording(1'b0),.pedal_clear(1'b0),.touch_voice_count(5'd0));
    reg [511:0] incoming=0,replies[0:511],message;
    reg [7:0] byte_value;integer reply_count=0,next_reply=0,bit_number;
    reg [3:0] last_bend;reg [15:0] last_ratio;
    always @(posedge clk)if(bend_write)begin last_bend<=bend_index;last_ratio<=bend_ratio;end
    initial forever begin
        @(negedge tx);repeat(25)@(posedge clk);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
            repeat(50)@(posedge clk);byte_value[bit_number]=tx;
        end
        repeat(50)@(posedge clk);if(tx!==1)$fatal(1,"UART framing");
        incoming={incoming[503:0],byte_value};
        if(byte_value==10)begin replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;end
    end
    task send;
        input [511:0] msg,expected;integer j,b,length,timeout;reg [511:0] tmp;
        begin
            tmp=msg;length=0;while(tmp!=0)begin length=length+1;tmp=tmp>>8;end
            for(j=length-1;j>=0;j=j-1)begin
                @(negedge clk);rx=0;repeat(50)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=msg[j*8+b];repeat(50)@(negedge clk);end
                rx=1;repeat(50)@(negedge clk);
            end
            timeout=0;while(reply_count<=next_reply && timeout<100000)begin @(negedge clk);timeout=timeout+1;end
            if(reply_count<=next_reply || replies[next_reply]!==expected)$fatal(1,"UART %0s got %0s expected %0s",msg,replies[next_reply],expected);
            next_reply=next_reply+1;
        end
    endtask
    integer key,n,checks=0;
    initial begin
        repeat(4)@(negedge clk);resetn=1;repeat(30)@(negedge clk);
        send("VIS,0,228\015","OK\015\012");
        if(dut.game_settings!==228)$fatal(1,"game settings not applied");
        send("VIS?\015","VIS,0,0,0,0,0,0,0\015\012");
        dashboard=1;send("VIS?\015","VIS,0,0,0,0,0,0,4\015\012");dashboard=0;
        send("VIS,0,256\015","ERR,RANGE\015\012");
        send("VIS,1,228\015","ERR,RANGE\015\012");
        send("VIS,0,\015","ERR,CMD\015\012");
        send("VIS,3\015","OK\015\012");
        if(dut.remote_mode!==3)$fatal(1,"legacy page selection changed");
        send("SONG_CHORD,?\015","OK\015\012");
        send("SONG_BEGIN,4\015","OK\015\012");
        send("SONG_CHORD,0,8193,900\015","OK\015\012");
        send("SONG_CHORD,1,16386,200\015","OK\015\012");
        send("SONG_CHORD,2,24596,100\015","OK\015\012");
        send("SONG_CHORD,3,32800,300,16384\015","OK\015\012");
        send("SONG_END\015","OK\015\012");
        if(dut.u_download.score[256][46:45]!==0 || dut.u_download.score[257][46:45]!==1 ||
            dut.u_download.score[258][46:45]!==2 || dut.u_download.score[259][46:45]!==3)
            $fatal(1,"UART typed masks did not reach the chart RAM");
        send("SONG_BEGIN,1\015","OK\015\012");
        send("SONG_CHORD,0,40961,100\015","ERR,RANGE\015\012");
        send("SONG_CHORD,0,8192,100\015","ERR,RANGE\015\012");
        send("MAP?\015","MAP,60,61,62,63,64,65,66,67,68,69,70,71\015\012");
        for(key=1;key<=12;key=key+1)begin
            for(n=60;n<=72;n=n+1)begin
                $sformat(message,"MAP,%0d,%0d%c",key,n,13);send(message,"OK\015\012");
                if(note_map[(key-1)*8+:8]!==n[7:0])$fatal(1,"Compact map key%0d pitch%0d",key,n);checks=checks+1;
            end
            $sformat(message,"BEND,%0d,%0d%c",key,12000+key,13);send(message,"OK\015\012");
            if(last_bend!==key-1 || last_ratio!==12000+key)$fatal(1,"BEND index %0d",key);checks=checks+1;
        end
        send("MAP?\015","MAP,72,72,72,72,72,72,72,72,72,72,72,72\015\012");
        send("MAP,13,60\015","ERR,KEY\015\012");send("MAP,12,73\015","ERR,NOTE\015\012");
        send("BEND,13,16384\015","ERR,RANGE\015\012");
        send("MAP_RESET\015","OK,MAP_RESET\015\012");
        send("MAP?\015","MAP,60,61,62,63,64,65,66,67,68,69,70,71\015\012");
        $display("PASS control12 protocol: all12 keys x13 pitches, two-digit keys, all12 BEND addresses, compact MAP query/reset, strict bounds; %0d checks, %0d replies",checks,next_reply);$finish;
    end
    initial begin #100000000;$fatal(1,"Protocol timeout");end
endmodule
