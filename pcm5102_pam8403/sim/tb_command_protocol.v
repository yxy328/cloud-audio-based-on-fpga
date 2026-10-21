`timescale 1ns/1ps
module tb_command_protocol;
    localparam BIT_TICKS=100;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1,ready=0,song=0,notes=0,recording=0;
    wire tx;
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
    initial begin
        expected_count=0;repeat(5)@(negedge clk);resetn=1;ready=1;
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,4000",8'd13,"\n"});
        transact("PITCH,15918,16864,5\n",20,{"OK",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,3E2E,41E0,0005,4000",8'd13,"\n"});
        transact("PITCH,8191\n",11,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,15919\n",12,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,,16863\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,,32769\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,,,0\n",10,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,,,65536\n",14,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,\n",7,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH,1,2,3,4,5\n",16,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH,,,x\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("pitch,?\n",8,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH, ?\n",9,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH,?x\n",9,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH,,,-1\n",11,{"ERR,CMD",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,3E2E,41E0,0005,4000",8'd13,"\n"});
        notes=1;song=1;
        transact("PITCH,8192,32768,4096\n",22,{"ERR,BUSY",8'd13,"\n"});
        transact("PITCH,,,256\n",12,{"OK",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,3E2E,41E0,0100,4000",8'd13,"\n"});
        notes=0;song=0;
        transact("PITCH,8192,32768,4096\n",22,{"OK",8'd13,"\n"});
        transact("PITCH,,,\n",9,{"OK",8'd13,"\n"});
        transact("PITCH,0000000000000000000000000000000000000000000000000000000000\n",65,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,00000000000000000000000000000000000000000000000000000000000\n",66,{"ERR,LENGTH",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,4000",8'd13,"\n"});
        recording=1;
        transact("PITCH,,,1\n",10,{"ERR,BUSY",8'd13,"\n"});
        recording=0;
        transact("BEND,1,32768\n",13,{"OK",8'd13,"\n"});
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        transact("VIB,?\n",6,{"VIB,0008,0D96,100,0000",8'd13,"\n"});
        transact("VIB,4,1739,1023,39063\n",22,{"OK",8'd13,"\n"});
        transact("VIB,?\n",6,{"VIB,0004,06CB,3FF,9897",8'd13,"\n"});
        transact("VIB,0,1,256,0\n",14,{"ERR,RANGE",8'd13,"\n"});
        transact("VIB,,,1024\n",11,{"ERR,RANGE",8'd13,"\n"});
        transact("VIB,,,,39064\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("VIB,11\n",7,{"ERR,RANGE",8'd13,"\n"});
        transact("VIB,1,2,3,4,5\n",14,{"ERR,CMD",8'd13,"\n"});
        transact("VIB,,,x\n",8,{"ERR,CMD",8'd13,"\n"});
        transact("vib,?\n",6,{"ERR,CMD",8'd13,"\n"});
        transact("VIB,?x\n",7,{"ERR,CMD",8'd13,"\n"});
        transact("VIB,?\n",6,{"VIB,0004,06CB,3FF,9897",8'd13,"\n"});
        notes=1;song=1;
        transact("VIB,10,48327,948,9766\n",22,{"OK",8'd13,"\n"});
        transact("VIB,?\n",6,{"VIB,000A,BCC7,3B4,2626",8'd13,"\n"});
        notes=0;song=0;recording=1;
        transact("VIB,,,0\n",8,{"ERR,BUSY",8'd13,"\n"});
        recording=0;
        transact("VIB,8,3478,256,0\n",17,{"OK",8'd13,"\n"});
        transact("VIB,,,,\n",8,{"OK",8'd13,"\n"});
        transact("VIB,?\n",6,{"VIB,0008,0D96,100,0000",8'd13,"\n"});
        transact("PITCH,,,,19573\n",15,{"OK",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,4C75",8'd13,"\n"});
        transact("ANALOG,2\n",9,{"ERR,STATE",8'd13,"\n"});
        transact("PITCH,,,,7726\n",14,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,,,,34705\n",15,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,8192,32768,4096,7726\n",27,{"ERR,RANGE",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,4C75",8'd13,"\n"});
        song=1;notes=1;
        transact("PITCH,,,,34704\n",15,{"OK",8'd13,"\n"});
        transact("PITCH,15918,16864,4096,7727\n",28,{"ERR,BUSY",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,8790",8'd13,"\n"});
        song=0;notes=0;
        transact("PITCH,,,,16384\n",15,{"OK",8'd13,"\n"});
        transact("ANALOG,2\n",9,{"OK",8'd13,"\n"});
        transact("PITCH,,,,19573\n",15,{"ERR,STATE",8'd13,"\n"});
        transact("PITCH,?\n",8,{"PITCH,2000,8000,1000,4000",8'd13,"\n"});
        transact("ANALOG,0\n",9,{"OK",8'd13,"\n"});
        transact("EFFECT2,?\n",10,{"EFFECT2,0",8'd13,"\n"});
        transact("EFFECT2,3\n",10,{"OK",8'd13,"\n"});
        transact("EFFECT2,?\n",10,{"EFFECT2,3",8'd13,"\n"});
        transact("EFFECT2,4\n",10,{"ERR,RANGE",8'd13,"\n"});
        transact("EFFECT2,65536\n",14,{"ERR,RANGE",8'd13,"\n"});
        transact("EFFECT2,-1\n",11,{"ERR,CMD",8'd13,"\n"});
        transact("EFFECT2,0,1\n",12,{"ERR,CMD",8'd13,"\n"});
        transact("EFFECT2,x\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("EFFECT2,\n",9,{"ERR,CMD",8'd13,"\n"});
        transact("effect2,?\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("EFFECT2,?\n",10,{"EFFECT2,3",8'd13,"\n"});
        notes=1;song=1;
        transact("EFFECT2,1\n",10,{"OK",8'd13,"\n"});
        transact("EFFECT2,?\n",10,{"EFFECT2,1",8'd13,"\n"});
        notes=0;song=0;recording=1;
        transact("EFFECT2,2\n",10,{"ERR,BUSY",8'd13,"\n"});
        recording=0;
        transact("EFFECT2,?\n",10,{"EFFECT2,1",8'd13,"\n"});
        transact("EFFECT2,0\n",10,{"OK",8'd13,"\n"});
        transact("EFFECT2,00000000000000000000000000000000000000000000000000000000\n",65,{"OK",8'd13,"\n"});
        transact("EFFECT2,000000000000000000000000000000000000000000000000000000000\n",66,{"ERR,LENGTH",8'd13,"\n"});
        transact("EFFECT2,?\n",10,{"EFFECT2,0",8'd13,"\n"});
        transact("TEMP,?\n",7,{"ERR,CMD",8'd13,"\n"});
        $display("PASS performance protocol: %0d wire-level replies, sparse fields, atomic rejection, busy guards, 64/65-byte frames",reply_count);$finish;
    end
    initial begin #200000000;$fatal(1,"Performance protocol timeout");end
endmodule
