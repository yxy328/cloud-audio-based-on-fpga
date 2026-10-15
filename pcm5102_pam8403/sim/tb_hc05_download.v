`timescale 1ns/1ps
// Full UART -> double-buffered stores / logger integration at real 50MHz.
module tb_hc05_download;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,rx=1;
    reg [6:0] keys=0;
    reg [15:0] gain=39321,ratio=65535;
    reg mode=0;
    reg [9:0] divider=0;
    always @(posedge clk) divider<=divider+1'b1;
    wire sample_ce=divider==0;
    wire tx,rec_busy,valid,playing,gate,pcm_valid,pcm_playing;
    wire [55:0] map;
    wire [31:0] increment;
    wire [6:0] guide;
    wire signed [15:0] pcm;
    reg [511:0] lines[0:255],incoming=0;
    integer lengths[0:255];
    integer line_count=0,line_length=0,next_line=0,b,events=0;
    reg [7:0] decoded;
    hc05_keymap #(.CLK_HZ(50000000),.BAUD(500000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(playing || pcm_playing),.notes_busy(|keys),.recording(1'b0),.note_map(map),
        .touch_keys(keys),.pressure_mode(mode),.volume_gain(gain),.pitch_ratio(ratio),
        .sample_ce(sample_ce),.toggle_play(1'b0),.restart(1'b0),.rec_busy(rec_busy),
        .downloaded_valid(valid),.downloaded_playing(playing),.downloaded_gate(gate),
        .downloaded_increment(increment),.guide_keys(guide),.pcm_valid(pcm_valid),.pcm_playing(pcm_playing),
        .pcm_sample(pcm),.builtin_play(),.builtin_stop());
    initial forever begin
        @(negedge tx); repeat(BIT_TICKS/2) @(posedge clk);
        for(b=0;b<8;b=b+1) begin repeat(BIT_TICKS) @(posedge clk); decoded[b]=tx; end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"Bad UART stop");
        incoming={incoming[503:0],decoded}; line_length=line_length+1;
        if(decoded==10) begin
            lines[line_count]=incoming; lengths[line_count]=line_length; line_count=line_count+1;
            incoming=0; line_length=0;
        end
    end
    task send;
        input [1023:0] text;
        input integer size;
        integer i,j;
        begin
            for(i=size-1;i>=0;i=i-1) begin
                @(negedge clk);rx=0;repeat(BIT_TICKS) @(negedge clk);
                for(j=0;j<8;j=j+1) begin rx=text[i*8+j];repeat(BIT_TICKS) @(negedge clk);end
                rx=1;repeat(BIT_TICKS) @(negedge clk);
            end
        end
    endtask
    task expect_line;
        input [511:0] text;
        begin
            wait(line_count>next_line);
            if(lines[next_line]!==text) $fatal(1,"Line %0d expected '%0s', got '%0s'",next_line,text,lines[next_line]);
            next_line=next_line+1;
        end
    endtask
    task transact;
        input [1023:0] text;
        input integer size;
        input [511:0] expected;
        begin send(text,size);expect_line(expected);end
    endtask
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,1,67,500\n",19,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"ERR,MISSING",8'd13,8'd10});
        if(valid) $fatal(1,"Incomplete score committed");
        transact("SONG_NOTE,0,60,500\n",19,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,0,60,50\n",18,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,1,67,0\n",17,{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        if(!valid) $fatal(1,"Valid score did not commit");
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,0,69,20\n",18,{"OK",8'd13,8'd10});
        // Disconnect: leave staging incomplete, then play original active score.
        repeat(10000) @(negedge clk);
        transact("PLAY\n",5,{"OK",8'd13,8'd10});
        if(!playing || guide!==1 || increment!==23012828) $fatal(1,"Interrupted score replaced old score");
        transact("MAP_RESET\n",10,{"ERR,BUSY",8'd13,8'd10});
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        if(playing || guide!=0) $fatal(1,"STOP failed");
        transact("MAP,1,62\n",9,{"OK,MAP,1,62",8'd13,8'd10});
        transact("PLAY\n",5,{"ERR,MAP",8'd13,8'd10});
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        transact("SONG_NOTE,0,60,65536\n",21,{"ERR,RANGE",8'd13,8'd10});
        // PCM: 16 signed 8-bit samples, checksum 8*0 + 8*128 = 1024.
        transact("PCM_BEGIN,16,1024\n",18,{"OK",8'd13,8'd10});
        transact("PCM_DATA,0,00000000000000008080808080808080\n",44,{"OK",8'd13,8'd10});
        transact("PCM_DATA,0,00000000000000008080808080808080\n",44,{"OK",8'd13,8'd10});
        transact("PCM_END\n",8,{"OK",8'd13,8'd10});
        if(!pcm_valid) $fatal(1,"PCM not committed");
        transact("PCM_BEGIN,16,0\n",15,{"OK",8'd13,8'd10});
        transact("PCM_DATA,0,01010101010101010101010101010101\n",44,{"OK",8'd13,8'd10});
        transact("PCM_END\n",8,{"ERR,CHECKSUM",8'd13,8'd10});
        transact("PCM_PLAY\n",9,{"OK",8'd13,8'd10});
        if(!pcm_playing) $fatal(1,"PCM not playing after interrupted/rejected download");
        wait(pcm==-32768);
        wait(!pcm_playing);
        transact("PCM_PLAY\n",9,{"OK",8'd13,8'd10});
        transact("PCM_STOP\n",9,{"OK",8'd13,8'd10});
        if(pcm_playing || pcm!==0) $fatal(1,"PCM_STOP failed");
        transact("PCM_DATA,0,GG\n",14,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_DATA,0,0\n",13,{"ERR,CMD",8'd13,8'd10});
        transact("REC_START\n",10,{"OK",8'd13,8'd10});
        expect_line({"MAP,60,62,64,65,67,69,71",8'd13,8'd10});
        expect_line({"EVT,0,00,0,39321,65535",8'd13,8'd10});
        transact("MAP,1,67\n",9,{"ERR,BUSY",8'd13,8'd10});
        @(negedge clk);keys=1;
        wait(line_count>next_line);
        if((lines[next_line] >> ((lengths[next_line]-4)*8))!=="EVT,") $fatal(1,"Key event absent");
        next_line=next_line+1;
        @(negedge clk);keys=3;
        wait(line_count>next_line);next_line=next_line+1;
        // Long hold emits no duplicate key snapshots without expression changes.
        repeat(100000) @(negedge clk);
        if(line_count!=next_line) $fatal(1,"Unchanged hold produced event");
        @(negedge clk);keys=0;
        wait(line_count>next_line);next_line=next_line+1;
        transact("REC_STOP\n",9,{"OK",8'd13,8'd10});
        wait(line_count>next_line);next_line=next_line+1; // final EVT
        expect_line({"REC_END,0",8'd13,8'd10});
        wait(!rec_busy);
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        $display("PASS [HC05 downloads]: UART score atomicity/retry/map validation, PCM hex download/checksum/play/stop, recording framing/map lock/initial/final states");
        $finish;
    end
    initial begin #200000000;$fatal(1,"Download protocol timeout state=%0d next=%0d lines=%0d",dut.state,next_line,line_count);end
endmodule
