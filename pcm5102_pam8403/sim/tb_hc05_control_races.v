`timescale 1ns/1ps
// Regressions for two races between the hardware PLAY button and UART.
// Commands and replies use the real UART; only the second test injects a
// stale completion pulse on the exact request-acceptance edge.
module tb_hc05_control_races;
    localparam integer BIT_TICKS=20;
    localparam [55:0] DEFAULT_MAP={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, rx=1, toggle_play=0, restart=0;
    wire tx, valid, playing, audition;
    wire [55:0] note_map;
    hc05_keymap #(
        .CLK_HZ(1000000),.BAUD(50000),.ENABLE_LOOKAHEAD(1)
    ) dut (
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(1'b1),
        .song_busy(playing || toggle_play),.notes_busy(1'b0),.recording(1'b0),
        .note_map(note_map),.touch_keys(7'd0),.pressure_mode(1'b0),
        .volume_gain(16'd39321),.pitch_ratio(16'd65535),
        .toggle_play(toggle_play),.restart(restart),.rec_busy(),
        .downloaded_valid(valid),.downloaded_playing(playing),.downloaded_gate(),
        .downloaded_audition(audition),
        .downloaded_increment(),.guide_keys(),.guide_ms_tick(),.guide_reset(),
        .note_spawn(),.spawn_keys(),.spawn_delay_ms(),.note_ready(1'b1),
        .builtin_play(),.builtin_stop()
    );
    reg [255:0] incoming=0;
    reg [255:0] replies[0:255];
    reg [7:0] received;
    integer reply_count=0, next_reply=0, bit_index;
    initial forever begin
        @(negedge tx);
        repeat(BIT_TICKS/2) @(posedge clk);
        if(tx !== 0) $fatal(1,"invalid TX start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(BIT_TICKS) @(posedge clk);
            received[bit_index]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx !== 1) $fatal(1,"invalid TX stop bit");
        incoming={incoming[247:0],received};
        if(received==10) begin
            replies[reply_count]=incoming;
            reply_count=reply_count+1;
            incoming=0;
        end
    end
    task send_byte;
        input [7:0] value;
        integer b;
        begin
            @(negedge clk); rx=0;
            repeat(BIT_TICKS) @(negedge clk);
            for(b=0;b<8;b=b+1) begin
                rx=value[b]; repeat(BIT_TICKS) @(negedge clk);
            end
            rx=1; repeat(BIT_TICKS) @(negedge clk);
        end
    endtask
    task send;
        input [1023:0] text;
        input integer size;
        integer b;
        begin
            for(b=size-1;b>=0;b=b-1)
                send_byte(text[b*8 +: 8]);
        end
    endtask
    task expect_reply;
        input [255:0] text;
        begin
            wait(reply_count>next_reply);
            if(replies[next_reply] !== text)
                $fatal(1,"reply %0d expected '%0s' got '%0s'",
                    next_reply,text,replies[next_reply]);
            next_reply=next_reply+1;
        end
    endtask
    task transact;
        input [1023:0] text;
        input integer size;
        input [255:0] expected;
        begin send(text,size); expect_reply(expected); end
    endtask

    reg [1023:0] command;
    integer i;
    reg locked_window_seen=0;
    initial begin
        repeat(5) @(negedge clk); resetn=1;
        // A full score keeps hardware-triggered validation active for 384
        // fabric clocks. All setup commands traverse the real RX/parser/RAM.
        transact("SONG_BEGIN,128\n",15,{"OK",8'd13,8'd10});
        for(i=0;i<128;i=i+1) begin
            command="SONG_NOTE,000,60,1000\n";
            command[95:88]=8'd48+i/100;
            command[87:80]=8'd48+(i/10)%10;
            command[79:72]=8'd48+i%10;
            transact(command,22,{"OK",8'd13,8'd10});
        end
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        if(!valid || playing) $fatal(1,"test score not committed/idle");

        // Queue all MAP characters, then press S1 before its EOL. The EOL
        // arrives after the one-cycle button pulse, during CHECK, when
        // playing is still false. Only download_busy can lock this interval.
        send("MAP,1,62",8);
        @(negedge clk); toggle_play=1;
        @(negedge clk); toggle_play=0;
        fork
            begin send_byte(10); end
            begin
                wait(dut.state==1); #1;
                if(playing || toggle_play || !dut.download_busy || dut.edit_allowed !== 0)
                    $fatal(1,"MAP did not execute in the protected validation window");
                if(dut.u_download.checked_map !== DEFAULT_MAP)
                    $fatal(1,"hardware validation did not snapshot original mapping");
                locked_window_seen=1;
            end
        join
        expect_reply({"ERR,BUSY",8'd13,8'd10});
        if(!locked_window_seen || note_map !== DEFAULT_MAP)
            $fatal(1,"MAP changed while hardware playback was validating");
        if(!playing) $fatal(1,"hardware playback validation did not complete");
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        transact("MAP,1,60\n",9,{"OK,MAP,1,60",8'd13,8'd10});

        // A physical action during UART validation cancels its pending
        // audition arm, even if the score validation completes later.
        fork
            begin send("AUDITION\n",9); end
            begin
                wait(dut.song_request && dut.song_operation==4);
                @(negedge clk);toggle_play=1;
                @(negedge clk);toggle_play=0;
            end
        join
        expect_reply({"OK",8'd13,8'd10});
        if(audition) $fatal(1,"Late UART completion rearmed cancelled audition");
        transact("AUDITION\n",9,{"OK",8'd13,8'd10});
        if(!audition) $fatal(1,"Explicit audition did not arm");
        @(negedge clk);restart=1;
        @(negedge clk);restart=0;
        repeat(500) @(negedge clk);
        if(audition) $fatal(1,"Physical restart retained audition");
        transact("AUDITION\n",9,{"OK",8'd13,8'd10});
        @(negedge clk);toggle_play=1;
        @(negedge clk);toggle_play=0;
        repeat(5) @(negedge clk);
        if(audition || playing) $fatal(1,"Physical stop retained audition/playback");

        // Real UART submits an invalid BEGIN. Inject a successful OLD
        // completion while song_request is high (the acceptance edge).
        // The genuine command simultaneously generates ERR,RANGE. The
        // parser must ignore old OK and consume ERR,RANGE on the next edge.
        fork
            begin send("SONG_BEGIN,0\n",13); end
            begin
                @(posedge dut.song_request);
                @(negedge clk);
                force dut.song_done=1'b1;
                force dut.song_error=3'd0;
                @(posedge clk); #1;
                if(dut.state !== 4)
                    $fatal(1,"stale completion stole a new UART command reply");
                @(negedge clk);
                release dut.song_done;
                release dut.song_error;
            end
        join
        expect_reply({"ERR,RANGE",8'd13,8'd10});
        // The guard must preserve ordinary immediate and delayed replies.
        transact("SONG_BEGIN,1\n",13,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,0,60,1\n",17,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("PING\n",5,{"PONG",8'd13,8'd10});
        repeat(2000) @(negedge clk);
        if(reply_count!=next_reply) $fatal(1,"unsolicited/duplicate UART reply");
        $display("PASS tb_hc05_control_races: real UART map lock during hardware validation, stale completion rejection, ordinary immediate/delayed ACKs");
        $finish;
    end
    initial begin #50000000; $fatal(1,"control race test timeout state=%0d replies=%0d next=%0d",dut.state,reply_count,next_reply); end
endmodule
