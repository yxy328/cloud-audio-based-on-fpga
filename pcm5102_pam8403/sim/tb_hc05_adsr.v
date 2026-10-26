`timescale 1ns/1ps
// Bit-level UART tests; accelerated divisor, independent TX decoder.
module tb_hc05_adsr;
    localparam BIT_TICKS=100;
    localparam [55:0] DEFAULT_MAP={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
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
        .toggle_play(1'b0),.restart(1'b0));
    midi_note_lut lut(.clk(clk),.resetn(resetn),.note_map(map),.phase_increments(base_steps));
    fsr_pitch_scaler scaler(.score_ratio(16'd0),.score_keys(7'd0),.bend_min(16'd8192),.bend_max(16'd32768),.bend_slew(16'd4096),.clk(clk),.resetn(resetn),.sample_ce(1'b1),.pitch_ratio(ratio),
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
        expected_count=0;repeat(5) @(negedge clk);resetn=1;ready=1;notes=1;song=1;recording=1;
        transact("ADSR,TOUCH,10,80,60,200\n",24,{"OK",8'd13,"\n"});
        if(dut.touch_adsr!=={16'd488,16'd3906,16'd39321,16'd9766} || dut.sensor_adsr!==0) $fatal(1,"UART touch profile conversion/independence");
        transact("ADSR,SENSOR,1000,0,100,1000\n",28,{"OK",8'd13,"\n"});
        if(!dut.sensor_adsr[129] || dut.sensor_adsr[128:113]!=48828 || dut.sensor_adsr[112:97]!=1 || dut.sensor_adsr[80:72]!=256 || dut.sensor_adsr[96:81]!=48828) $fatal(1,"Sensor bounds");
        transact("ADSR,TOUCH,1001,2,50,4\n",23,{"ERR,RANGE",8'd13,"\n"});
        transact("ADSR,TOUCH,1,1001,50,4\n",23,{"ERR,RANGE",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,101,4\n",21,{"ERR,RANGE",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,50,1001\n",23,{"ERR,RANGE",8'd13,"\n"});
        transact("ADSR,TOUCH,65536,2,50,4\n",24,{"ERR,RANGE",8'd13,"\n"});
        transact("ADSR,TOUCH,-1,2,50,4\n",21,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCH,1,,50,4\n",19,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,50\n",18,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,50,4,5\n",22,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,50,4,\n",21,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCH,1,2,50,X\n",20,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,OTHER,1,2,50,4\n",20,{"ERR,CMD",8'd13,"\n"});
        transact("ADSR,TOUCHX,1,2,50,4\n",21,{"ERR,CMD",8'd13,"\n"});
        if(dut.touch_adsr!=={16'd488,16'd3906,16'd39321,16'd9766} || dut.sensor_adsr[128:113]!=48828) $fatal(1,"Invalid ADSR partially changed profiles");
        transact("ADSR,TOUCH,0,0,0,0\n",19,{"OK",8'd13,"\n"});
        if(dut.touch_adsr!=={16'd1,16'd1,16'd0,16'd1}) $fatal(1,"Zero duration minimum");
        transact("ADSR_RESET,TOUCH\n",17,{"OK",8'd13,"\n"});
        if(dut.touch_adsr!=={16'd98,16'd3906,16'd39321,16'd488} || !dut.sensor_adsr[129]) $fatal(1,"Touch restore altered sensor profile");
        transact("ADSR_RESET,SENSOR\n",18,{"OK",8'd13,"\n"});
        if(dut.sensor_adsr!==0) $fatal(1,"Restore sensor legacy envelope");
        transact("ADSR,SENSOR,0001,0002,050,0003\n",31,{"OK",8'd13,"\n"});
        if(dut.sensor_adsr[128:113]!=49 || dut.sensor_adsr[112:97]!=98 || dut.sensor_adsr[80:72]!=128 || dut.sensor_adsr[96:81]!=146) $fatal(1,"Leading zeros");
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        $display("PASS UART ADSR: %0d replies; profile conversion, strict four fields, bounds/zero, invalid-command atomicity, controls while notes/score busy, independent restore",reply_count);$finish;
    end
    initial begin #100000000;$fatal(1,"ADSR UART timeout");end
endmodule
