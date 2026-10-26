`timescale 1ns/1ps
// Full UART -> double-buffered stores / logger integration at real 50MHz.
module tb_hc05_download_current;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,rx=1;
    reg [6:0] keys=0;
    reg [15:0] gain=39321,ratio=65535;
    reg mode=0;
    reg [9:0] divider=0;
    always @(posedge clk) divider<=divider+1'b1;
    wire sample_ce=divider==0;
    wire tx,rec_busy,valid,playing,gate,audition;
    wire [55:0] map;
    wire [31:0] increment;
    wire [6:0] guide;
    reg [511:0] lines[0:255],incoming=0;
    integer lengths[0:255];
    integer line_count=0,line_length=0,next_line=0,b,events=0;
    reg [7:0] decoded;
    hc05_keymap #(.CLK_HZ(50000000),.BAUD(500000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(playing),.notes_busy(|keys),.recording(1'b0),.note_map(map),
        .touch_keys(keys),.pressure_mode(mode),.volume_gain(gain),.pitch_ratio(ratio),
        .toggle_play(1'b0),.restart(1'b0),.rec_busy(rec_busy),
        .downloaded_valid(valid),.downloaded_playing(playing),.downloaded_gate(gate),
        .downloaded_audition(audition),
        .downloaded_increment(increment),.guide_keys(guide),.builtin_play(),.builtin_stop());
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
    task natural_mapping;begin
        transact("MAP,2,62\n",9,{"OK,MAP,2,62",8'd13,8'd10});
        transact("MAP,3,64\n",9,{"OK,MAP,3,64",8'd13,8'd10});
        transact("MAP,4,65\n",9,{"OK,MAP,4,65",8'd13,8'd10});
        transact("MAP,5,67\n",9,{"OK,MAP,5,67",8'd13,8'd10});
        transact("MAP,6,69\n",9,{"OK,MAP,6,69",8'd13,8'd10});
        transact("MAP,7,71\n",9,{"OK,MAP,7,71",8'd13,8'd10});
    end endtask
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        transact("AUDITION\n",9,{"ERR,STATE",8'd13,8'd10});
        if(audition) $fatal(1,"No-score audition armed audio");
        natural_mapping;
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
        if(audition) $fatal(1,"PLAY unexpectedly armed audition");
        transact("AUDITION\n",9,{"OK",8'd13,8'd10});
        if(!audition || !playing) $fatal(1,"Valid score audition did not start");
        transact("PLAY\n",5,{"OK",8'd13,8'd10});
        if(audition) $fatal(1,"PLAY did not clear audition");
        transact("MAP_RESET\n",10,{"ERR,BUSY",8'd13,8'd10});
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        if(playing || guide!=0) $fatal(1,"STOP failed");
        transact("MAP,1,62\n",9,{"OK,MAP,1,62",8'd13,8'd10});
        transact("PLAY\n",5,{"ERR,MAP",8'd13,8'd10});
        transact("AUDITION\n",9,{"ERR,MAP",8'd13,8'd10});
        if(audition) $fatal(1,"Invalid map armed audition");
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        transact("SONG_NOTE,0,60,65536\n",21,{"ERR,RANGE",8'd13,8'd10});
        natural_mapping;
        // Pre-recorded sample download/play commands are deliberately absent.
        transact("PCM_BEGIN,16,1024\n",18,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_DATA,0,00000000000000008080808080808080\n",44,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_END\n",8,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_PLAY\n",9,{"ERR,CMD",8'd13,8'd10});
        // Chord mask bit0=C4, bit4=E4, bit7=G4; zero is an explicit rest.
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,145,2\n",19,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,1,0,2\n",17,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,1,8192,50\n",21,{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("PLAY\n",5,{"OK",8'd13,8'd10});
        if(guide!==7'h15) $fatal(1,"Chord mask not mapped to three simultaneous keys");
        wait(guide==0);
        if(!playing) $fatal(1,"Explicit rest did not retain score timing");
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        transact("SONG_BEGIN,1\n",13,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,2,50\n",18,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"ERR,MAP",8'd13,8'd10});
        // Fixed16 already rejects this legacy seven-key event logger.
        transact("REC_START\n",10,{"ERR,BUSY",8'd13,8'd10});
        if(rec_busy)$fatal(1,"Fixed16 unexpectedly enabled legacy logger");
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        transact("MAP?\n",5,{"MAP,60,61,62,63,64,65,66",8'd13,8'd10});
        if(map!=={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60})
            $fatal(1,"Current chromatic reset map changed");
        $display("PASS current downloads: original score atomicity/retry/bounds, chromatic chord/rest, fixed16 legacy guard and MAP reset");
        $finish;
    end
    initial begin #200000000;$fatal(1,"Download protocol timeout state=%0d next=%0d lines=%0d",dut.state,next_line,line_count);end
endmodule
