`timescale 1ns/1ps
// Bit-level UART tests; accelerated divisor, independent TX decoder.
module tb_hc05_bend;
    localparam BIT_TICKS=100;
    localparam [55:0] DEFAULT_MAP={8'd71,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,rx=1,ready=0,song=0,notes=0,recording=0;
    wire tx,wr,rst;
    wire [2:0] bkey;
    wire [15:0] bratio;
    integer writes=0,resets=0;
    always @(negedge clk) begin if(wr)writes=writes+1;if(rst)resets=resets+1;end
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
        .toggle_play(1'b0),.restart(1'b0),.bend_write(wr),.bend_reset(rst),.bend_index(bkey),.bend_ratio(bratio));
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
        expected_count=0;repeat(5)@(negedge clk);resetn=1;ready=1;notes=1;song=1;recording=1;
        transact("BEND,1,8192\n",12,{"OK",8'd13,"\n"});
        if(bkey!=0 || bratio!=8192)$fatal(1,"Bend payload");
        transact("BEND,7,32768\n",13,{"OK",8'd13,"\n"});
        if(bkey!=6 || bratio!=32768)$fatal(1,"Bend payload");
        transact("BEND,4,16384\n",13,{"OK",8'd13,"\n"});
        if(bkey!=3 || bratio!=16384)$fatal(1,"Bend payload");
        transact("BEND,0,16384\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("BEND,8,16384\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("BEND,1,8191\n",12,{"ERR,RANGE",8'd13,"\n"});
        transact("BEND,1,32769\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("BEND,1,65536\n",13,{"ERR,RANGE",8'd13,"\n"});
        transact("BEND,1,-1\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("BEND,1\n",7,{"ERR,CMD",8'd13,"\n"});
        transact("BEND,1,\n",8,{"ERR,CMD",8'd13,"\n"});
        transact("BEND,,16384\n",12,{"ERR,CMD",8'd13,"\n"});
        transact("BEND,1,16384,2\n",15,{"ERR,CMD",8'd13,"\n"});
        transact("BEND,1,16384,\n",14,{"ERR,CMD",8'd13,"\n"});
        transact("BENDX,1,16384\n",14,{"ERR,CMD",8'd13,"\n"});
        transact("BEND_RESETX\n",12,{"ERR,CMD",8'd13,"\n"});
        if(writes!=3 || resets!=0 || map!==DEFAULT_MAP)$fatal(1,"Invalid command mutated state");
        transact("BEND_RESET\n",11,{"OK",8'd13,"\n"});
        if(resets!=1 || writes!=3 || map!==DEFAULT_MAP)$fatal(1,"Reset pulse/map");
        transact("ADSR,TOUCH,0,0,50,0\n",20,{"OK",8'd13,"\n"});
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        $display("PASS UART bend: %0d replies, endpoints, exact voice address, strict fields/bounds/atomic rejection, busy playing allowed, reset, ADSR coexistence",reply_count);$finish;
    end
    initial begin #100000000;$fatal(1,"UART bend timeout");end
endmodule
