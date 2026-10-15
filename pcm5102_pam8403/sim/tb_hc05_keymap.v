`timescale 1ns/1ps
// Bit-level UART tests; accelerated divisor, independent TX decoder.
module tb_hc05_keymap;
    localparam BIT_TICKS=100;
    localparam [55:0] DEFAULT_MAP={8'd71,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,rx=1,ready=0,song=0,notes=0,recording=0;
    wire tx;
    wire [55:0] map;
    wire [223:0] base_steps;
    wire [255:0] steps;
    reg [15:0] ratio=65535;
    reg [255:0] replies[0:255];
    reg [255:0] incoming=0;
    reg [7:0] decoded;
    integer reply_count=0,bit_index,expected_count,n,k,old_count;
    real hz;
    reg [31:0] expected_step;
    reg [255:0] command;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),.keys_ready(ready),
        .song_busy(song),.notes_busy(notes),.recording(recording),.note_map(map),
        .touch_keys(7'd0),.pressure_mode(1'b0),.volume_gain(16'd39321),.pitch_ratio(16'd65535),
        .sample_ce(1'b0),.toggle_play(1'b0),.restart(1'b0));
    midi_note_lut lut(.clk(clk),.resetn(resetn),.note_map(map),.phase_increments(base_steps));
    fsr_pitch_scaler scaler(.clk(clk),.resetn(resetn),.sample_ce(1'b1),.pitch_ratio(ratio),
        .note_increments(base_steps),.phase_increments(steps));
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
        expected_count=0;
        repeat(5) @(negedge clk);resetn=1;
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        transact({"MAP?",8'd13,"\n"},6,{"MAP,60,62,64,65,67,69,71",8'd13,"\n"});
        transact("MAP,1,67\n",9,{"ERR,BUSY",8'd13,"\n"});
        ready=1;
        transact({"MAP,1,67",8'd13,"\n"},10,{"OK,MAP,1,67",8'd13,"\n"});
        if(map[7:0]!==67 || steps[31:0]!==34480283) $fatal(1,"G4 edit did not reach DDS step");
        transact("MAP?\n",5,{"MAP,67,62,64,65,67,69,71",8'd13,"\n"});
        notes=1;transact("MAP,1,60\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("MAP_RESET\n",10,{"ERR,BUSY",8'd13,"\n"});notes=0;
        song=1;transact("MAP,2,60\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        transact("MAP?\n",5,{"MAP,67,62,64,65,67,69,71",8'd13,"\n"});song=0;
        recording=1;transact("MAP_RESET\n",10,{"ERR,BUSY",8'd13,"\n"});recording=0;
        if(map[7:0]!==67) $fatal(1,"Busy command changed map");
        transact("MAP,0,60\n",9,{"ERR,KEY",8'd13,"\n"});
        transact("MAP,8,60\n",9,{"ERR,KEY",8'd13,"\n"});
        transact("MAP,1,59\n",9,{"ERR,NOTE",8'd13,"\n"});
        transact("MAP,1,73\n",9,{"ERR,NOTE",8'd13,"\n"});
        transact("MAP,1,6X\n",9,{"ERR,CMD",8'd13,"\n"});
        transact("MAP,1,067\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("MAP,1,67,\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("MAP,1,-1\n",9,{"ERR,CMD",8'd13,"\n"});
        transact("ping\n",5,{"ERR,CMD",8'd13,"\n"});
        transact(" MAP?\n",6,{"ERR,CMD",8'd13,"\n"});
        transact({{64{8'd88}},"MAP,1,60\n"},73,{"ERR,LENGTH",8'd13,"\n"});
        byte_out(0,1);byte_out(10,1);expect_reply({"ERR,CMD",8'd13,"\n"});
        send("MAP,1,60",8);old_count=reply_count;repeat(2000) @(negedge clk);
        if(reply_count!=old_count || map[7:0]!==67) $fatal(1,"Unterminated command executed");
        byte_out(13,1);expect_reply({"OK,MAP,1,60",8'd13,"\n"});
        // All 13 notes are compared to the mathematical DDS formula.
        for(n=60;n<=72;n=n+1) begin
            command="MAP,1,00\n";command[23:16]=48+n/10;command[15:8]=48+n%10;
            send(command,9);
            expect_reply({"OK,MAP,1,",command[23:8],{8'd13,"\n"}});
            hz=440.0*(2.0**((n-69)/12.0));expected_step=$rtoi(hz*4294967296.0/48828.125+0.5);
            if(base_steps[31:0]!==expected_step || steps[31:0]!==expected_step)
                $fatal(1,"MIDI %0d step disagrees with equal temperament",n);
            ratio=32768;repeat(12) @(negedge clk);
            if(steps[31:0]!==expected_step/2) $fatal(1,"Remapped pressure octave failed");
            ratio=65535;repeat(12) @(negedge clk);
        end
        // Every key is writable; duplicate pitches are deliberately allowed.
        for(k=1;k<=7;k=k+1) begin
            command="MAP,1,67\n";command[39:32]=48+k;
            send(command,9);expect_reply({"OK,MAP,",command[39:32],{",67",8'd13,"\n"}});
            if(map[(k-1)*8 +: 8]!==67 || steps[(k-1)*32 +: 32]!==34480283)
                $fatal(1,"Wrong key index changed");
        end
        transact("MAP?\n",5,{"MAP,67,67,67,67,67,67,67",8'd13,"\n"});
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,"\n"});
        if(map!==DEFAULT_MAP) $fatal(1,"Default reset failed");
        // A bad stop in a mutating command must invalidate the whole line.
        send("MAP,1,6",7);byte_out("7",0);byte_out(10,1);expect_reply({"ERR,UART",8'd13,"\n"});
        if(map!==DEFAULT_MAP) $fatal(1,"Corrupt UART frame modified map");
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        // Back-to-back queries queue while a longer reply is still sending.
        for(k=0;k<8;k=k+1) send("MAP?\n",5);
        for(k=0;k<8;k=k+1) expect_reply({"MAP,60,62,64,65,67,69,71",8'd13,"\n"});
        send({8'd13,"\n\n"},3);repeat(3000) @(negedge clk);
        if(reply_count!=expected_count) $fatal(1,"CRLF/blank line emitted extra response");
        transact("MAP,1,67\n",9,{"OK,MAP,1,67",8'd13,"\n"});
        @(negedge clk);resetn=0;repeat(5) @(negedge clk);resetn=1;
        repeat(12) @(negedge clk);
        if(map!==DEFAULT_MAP || steps[31:0]!==23012828) $fatal(1,"Power reset did not restore C4");
        $display("PASS [HC05 protocol]: %0d replies; all commands/keys/13 notes, exact DDS steps/pressure octave, busy guards, query bursts, CR/LF/CRLF, invalid/partial/long/binary lines, framing recovery and reset",reply_count);
        $finish;
    end
    initial begin #100000000;$fatal(1,"HC05 protocol timeout");end
endmodule
