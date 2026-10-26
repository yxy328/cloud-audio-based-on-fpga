`timescale 1ns/1ps
module tb_score_bend_protocol;
    localparam BIT_TICKS=100;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1,ready=0,song=0,notes=0,recording=0;
    wire tx;
    wire [2:0] cfg_mask;
    wire [7:0] cfg_settings;
    wire [11:0] cfg_mix;
    reg applied_override=0;
    wire [2:0] applied_mask=applied_override ? 3'd4 : cfg_mask;
    wire [7:0] applied_settings=applied_override ? 8'hd2 : cfg_settings;
    wire [11:0] applied_mix=applied_override ? 12'h800 : cfg_mix;
    reg [255:0] replies[0:255];
    reg [255:0] incoming=0;
    reg [7:0] decoded;
    integer reply_count=0,bit_index,expected_count;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),
        .resetn(resetn),
        .rx(rx),
        .keys_ready(ready),
        .song_busy(song),
        .notes_busy(notes),
        .recording(recording),
        .touch_keys(7'd0),
        .pressure_mode(1'd0),
        .volume_gain(16'd39321),
        .pitch_ratio(16'd65535),
        .toggle_play(1'd0),
        .restart(1'd0),
        .note_ready(1'd0),
        .visual_requested(2'd0),
        .reference_ratio(2'd0),
        .reference_phase(2'd0),
        .visual_snapshot(112'd0),
        .touch_voice_count(5'd0),
        .pedal_clear(1'd0),
        .take_recording(1'd0),
        .adc_sample(10'd0),
        .adc_timeout(1'd0),
        .audio_rec_busy(1'd0),
        .audio_rec_ready(1'd0),
        .audio_rec_overflow(1'd0),
        .audio_rec_valid(1'd0),
        .audio_rec_status(4'd0),
        .audio_rec_error(4'd0),
        .audio_rec_stored_samples(21'd0),
        .audio_rec_generation(16'd0),
        .audio_stream_data(8'd0),
        .audio_stream_valid(1'd0),
        .audio_stream_last(1'd0),
        .audio_stream_busy(1'd0),
        .take_flags(8'd0),
        .take_error(4'd0),
        .take_elapsed(24'd0),
        .take_duration(24'd0),
        .take_count(11'd0),
        .fx_mask(cfg_mask),.fx_settings(cfg_settings),.fx_mix(cfg_mix),
        .fx_applied_mask(applied_mask),.fx_applied_settings(applied_settings),.fx_applied_mix(applied_mix),
        .tx(tx)
    );
    initial forever begin
        @(negedge tx);
        repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"TX start bit invalid");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(BIT_TICKS) @(posedge clk); decoded[bit_index]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"TX stop bit invalid");
        incoming={incoming[247:0],decoded};
        if(decoded==10) begin
            replies[reply_count]=incoming; reply_count=reply_count+1; incoming=0;
        end
    end
    task byte_out;
        input [7:0] value;
        input good_stop;
        integer b;
        begin
            @(negedge clk);rx=0;repeat(BIT_TICKS) @(negedge clk);
            for(b=0;b<8;b=b+1) begin rx=value[b];repeat(BIT_TICKS) @(negedge clk);end
            rx=good_stop;repeat(BIT_TICKS) @(negedge clk);
            rx=1;
            if(!good_stop) repeat(BIT_TICKS) @(negedge clk);
        end
    endtask
    task send;
        input [1023:0] message;
        input integer length;
        integer b;
        begin for(b=length-1;b>=0;b=b-1) byte_out(message[b*8 +: 8],1);end
    endtask
    task expect_reply;
        input [255:0] expected;
        begin
            wait(reply_count>expected_count);
            if(replies[expected_count]!==expected)
                $fatal(1,"Reply %0d expected '%0s' got '%0s'",expected_count,expected,replies[expected_count]);
            expected_count=expected_count+1;
        end
    endtask
    task transact;
        input [1023:0] message;
        input integer length;
        input [255:0] expected;
        begin send(message,length);expect_reply(expected);end
    endtask
    integer m,trace;
    reg [1023:0] command_text;
    function [7:0] digit;input integer x;begin digit=x<10 ? 8'd48+x : 8'd55+x;end endfunction
    function integer length;input [1023:0] x;integer i;begin length=0;for(i=0;i<128;i=i+1)if(x[i*8 +: 8]!=0)length=i+1;end endfunction
    task query;input [255:0] value;begin transact("EFFECT,?\n",9,value);end endtask
    initial begin
        expected_count=0;repeat(5)@(negedge clk);resetn=1;ready=1;
        query({"EFFECT3,0,52,444,0,52,444",8'd13,8'd10});
        transact("EFFECT,3,7,255,2184\n",20,{"OK",8'd13,8'd10});
        query({"EFFECT3,7,FF,888,7,FF,888",8'd13,8'd10});
        transact("EFFECT,3,8,255,2184\n",20,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,3,7,256,2184\n",20,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,3,7,255,2185\n",20,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,3,7,255,4096\n",20,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,3,7,255\n",15,{"ERR,CMD",8'd13,8'd10});
        transact("EFFECT,3,7,255,2184,0\n",22,{"ERR,CMD",8'd13,8'd10});
        query({"EFFECT3,7,FF,888,7,FF,888",8'd13,8'd10});
        for(m=0;m<8;m=m+1)begin
            $sformat(command_text,"EFFECT,3,%0d,82,1092\n",m);
            transact(command_text,length(command_text),{"OK",8'd13,8'd10});
            query({"EFFECT3,",digit(m),",52,444,",digit(m),",52,444",8'd13,8'd10});
        end
        transact("EFFECT,1,3\n",11,{"OK",8'd13,8'd10});
        query({"EFFECT3,2,52,333,2,52,333",8'd13,8'd10});
        transact("EFFECT,2,6\n",11,{"OK",8'd13,8'd10});
        query({"EFFECT3,1,53,666,1,53,666",8'd13,8'd10});
        transact("EFFECT,0,4\n",11,{"OK",8'd13,8'd10});
        transact("EFFECT2,2\n",10,{"OK",8'd13,8'd10});
        transact("EFFECT2,?\n",10,{"EFFECT2,2",8'd13,8'd10});
        query({"EFFECT3,0,5B,444,0,5B,444",8'd13,8'd10});
        applied_override=1;
        query({"EFFECT3,0,5B,444,4,D2,800",8'd13,8'd10});
        applied_override=0;
        transact("SONG_BEGIN,?\n",13,{"SONGBEND,1",8'd13,8'd10});
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10,20000\n",24,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,1,2,10,12000\n",24,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10,1\n",20,{"ERR,STATE",8'd13,8'd10});
        transact("PITCH,15000,20000,4096\n",23,{"OK",8'd13,8'd10});
        transact("PLAY\n",5,{"ERR,RANGE",8'd13,8'd10});
        transact("PITCH,8192,32768,4096\n",22,{"OK",8'd13,8'd10});
        transact("SONG_BEGIN,1\n",13,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10,32769\n",24,{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10,8191\n",23,{"ERR,RANGE",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10,20000,0\n",26,{"ERR,CMD",8'd13,8'd10});
        transact("SONG_CHORD,0,1,10\n",18,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("SONG_BEGIN,?\n",13,{"SONGBEND,1",8'd13,8'd10});
        transact("PING\n",5,{"PONG",8'd13,8'd10});
        trace=$fopen("sim/build/score_bend_protocol_replies.txt","w");
        for(m=0;m<reply_count;m=m+1)$fwrite(trace,"%0s",replies[m]);
        $fclose(trace);
        $display("PASS FX protocol: %0d replies, all8 masks, atomic bounds, legacy0/1/2 and EFFECT2, configured/applied state",reply_count);$finish;
    end
    initial begin #100000000;$fatal(1,"FX protocol timeout replies=%0d",reply_count);end
endmodule
