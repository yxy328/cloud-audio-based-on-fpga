`timescale 1ns/1ps
module tb_hc05_extensions;
    localparam BIT_TICKS=100;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,rx=1,ready=1,song=0,notes=0,rec=0;
    wire tx,mode16,hold,panic,pwrite,pvalue;
    wire [1:0] effect;wire [3:0] wet;wire [4:0] volume;wire [2:0] analog;
    integer reply_count=0,bit_index,expected_count,panics=0,writes=0;
    reg [255:0] replies[0:255];reg [255:0] incoming=0;reg [7:0] decoded;
    hc05_keymap #(.BAUD(500000)) dut(.clk(clk),.resetn(rst),.rx(rx),.tx(tx),
        .keys_ready(ready),.song_busy(song),.notes_busy(notes),.recording(rec),
        .touch_keys(7'd0),.pressure_mode(1'b1),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .touch_mode16(mode16),.touch_hold(hold),.panic(panic),.effect_mode(effect),
        .effect_wet(wet),.master_volume(volume),.analog_mode(analog),
        .pressure_write(pwrite),.pressure_value(pvalue),.adc_sample(10'd1023),.adc_timeout(1'b0));
    always @(negedge clk)begin if(panic)panics=panics+1;if(pwrite)writes=writes+1;end
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
        expected_count=0;repeat(5)@(negedge clk);rst=1;
        transact("CTRL?\n",6,{"CTRL,1,0,4,0,0,16,1",8'd13,"\n"});
        ready=0;
        transact("SERIAL,1\n",9,{"OK",8'd13,"\n"});
        transact("SERIAL?\n",8,{"SERIAL,1",8'd13,"\n"});
        notes=1;transact("SERIAL,0\n",9,{"ERR,BUSY",8'd13,"\n"});notes=0;
        song=1;transact("SERIAL,0\n",9,{"ERR,BUSY",8'd13,"\n"});song=0;
        rec=1;transact("SERIAL,0\n",9,{"ERR,BUSY",8'd13,"\n"});rec=0;
        transact("SERIAL?\n",8,{"SERIAL,1",8'd13,"\n"});
        transact("SERIAL,0\n",9,{"OK",8'd13,"\n"});ready=1;
        transact("SERIAL?\n",8,{"SERIAL,0",8'd13,"\n"});
        transact("SERIAL,1\n",9,{"OK",8'd13,"\n"});
        transact("SERIAL?\n",8,{"SERIAL,1",8'd13,"\n"});
        transact("SERIAL,2\n",9,{"ERR,RANGE",8'd13,"\n"});
        transact("CAL?\n",5,{"CAL,000,3FF",8'd13,"\n"});
        transact("CAL,50,600\n",11,{"OK",8'd13,"\n"});
        transact("CAL?\n",5,{"CAL,032,258",8'd13,"\n"});
        transact("CAL,100,100\n",12,{"ERR,RANGE",8'd13,"\n"});
        transact("CAL,0,31\n",9,{"ERR,RANGE",8'd13,"\n"});
        transact("CAL,0,1024\n",11,{"ERR,RANGE",8'd13,"\n"});
        transact("ADC?\n",5,{"ADC,3FF,0",8'd13,"\n"});
        transact("TOUCH,16\n",9,{"OK",8'd13,"\n"});if(!mode16)$fatal(1,"Mode not committed");
        transact("REC_START\n",10,{"ERR,BUSY",8'd13,"\n"});
        transact("TOUCH,8\n",8,{"ERR,RANGE",8'd13,"\n"});notes=1;
        transact("TOUCH,16\n",9,{"ERR,BUSY",8'd13,"\n"});notes=0;song=1;
        transact("TOUCH,16\n",9,{"ERR,BUSY",8'd13,"\n"});song=0;rec=1;
        transact("TOUCH,16\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("ANALOG,1\n",9,{"ERR,BUSY",8'd13,"\n"});rec=0;
        transact("EFFECT,2,8\n",11,{"OK",8'd13,"\n"});
        transact("HOLD,1\n",7,{"OK",8'd13,"\n"});
        transact("TOUCH,16\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("VOLUME,0\n",9,{"OK",8'd13,"\n"});
        transact("ANALOG,4\n",9,{"OK",8'd13,"\n"});
        transact("PRESSURE,0\n",11,{"OK",8'd13,"\n"});if(writes!=1 || pvalue!=0)$fatal(1,"Pressure write pulse");
        transact("CTRL?\n",6,{"CTRL,1,2,8,1,4,00,1",8'd13,"\n"});
        transact("TOUCH,9\n",8,{"ERR,RANGE",8'd13,"\n"});
        transact("EFFECT,3,4\n",11,{"ERR,CMD",8'd13,"\n"});
        transact("EFFECT,1,9\n",11,{"ERR,RANGE",8'd13,"\n"});
        transact("EFFECT,1,4,0\n",13,{"ERR,CMD",8'd13,"\n"});
        transact("HOLD,3\n",7,{"ERR,RANGE",8'd13,"\n"});
        transact("VOLUME,17\n",10,{"ERR,RANGE",8'd13,"\n"});
        transact("ANALOG,5\n",9,{"ERR,RANGE",8'd13,"\n"});
        transact("PRESSURE,2\n",11,{"ERR,RANGE",8'd13,"\n"});
        transact("EFFECT,,4\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("VOLUME,-1\n",10,{"ERR,CMD",8'd13,"\n"});
        transact("CTRL?x\n",7,{"ERR,CMD",8'd13,"\n"});
        if(effect!=2 || wet!=8 || !hold || volume!=0 || analog!=4 || !mode16)$fatal(1,"Invalid commands mutated controls");
        transact("PANIC\n",6,{"OK",8'd13,"\n"});if(hold || panics!=1)$fatal(1,"Panic/hold release");
        transact("HOLD,0\n",7,{"OK",8'd13,"\n"});
        transact("TOUCH,16\n",9,{"OK",8'd13,"\n"});
        $display("PASS extension UART: %0d bit-level replies, state/ADC query, busy/recording gates, strict bounds/atomic rejection, panic",reply_count);$finish;
    end
    initial begin #100000000;$fatal(1,"Extension UART timeout replies %0d",reply_count);end
endmodule
