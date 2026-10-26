`timescale 1ns/1ps
module tb_top_touch16_recovery;
    localparam BIT_TICKS=100;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [7:0] pads=0;reg [15:0] keys=0;
    wire tx,bck,lrck,din,tscl,sdo,model_sdo;
    reg model_high=1;
    reg sensor_reset=0;
    assign sdo=model_high ? ~model_sdo : model_sdo;
    tri1 scl,sda;
    integer reply_count=0,bit_index,expected_count,frame=0,i,n,j;
    reg [255:0] replies[0:255];reg [255:0] incoming=0;reg [7:0] decoded;
    real co,si,angle,amp,window,weight;
    integer midi;
    integer start_sample;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16),.FSR_ENABLE(0)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.touch_sdo(sdo),.touch_scl(tscl),
        .ir_beam(8'hff),.hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.scl(scl),.sda(sda));
    ttp229_model chip(.rst_n(dut.resetn && !sensor_reset),.scl(model_high ? ~tscl : tscl),.connected(1'b1),.dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(model_sdo));
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor(.bck(bck),.lrck(lrck),.din(din));
    always @(negedge clk)if(dut.resetn && dut.frame_ce)begin
        frame=frame+1;if(dut.u_touch_synth.overrun || dut.sensor_overrun)$fatal(1,"Synthesis frame deadline");
    end
    task frames;input integer count;integer finish;begin finish=frame+count;wait(frame>=finish);@(negedge clk);end endtask
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
        expected_count=0;wait(dut.resetn);repeat(20000)@(negedge clk);
        if(dut.touch_ready)$fatal(1,"Wrong default polarity unexpectedly ready");
        transact("SERIAL,1\n",9,{"OK",8'd13,"\n"});
        wait(dut.touch_ready);frames(4);pads=255;frames(4);
        if(!dut.touch_mode16 || dut.touch_keys)$fatal(1,"Fixed16 recovery / GPIO isolation");
        keys=16'hffff;wait(dut.touch_keys==16'hffff);frames(20);
        if(dut.touch_active[6:0]!=127 || dut.extended_active!=511)$fatal(1,"Recovered high-active keys not voiced");
        transact("SERIAL,0\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("TOUCH,8\n",8,{"ERR,RANGE",8'd13,"\n"});
        keys=0;wait(dut.touch_keys==0);frames(30);
        if(dut.touch_active || dut.extended_active)$fatal(1,"Recovery note release");
        $display("PASS fixed16 recovery: high-active sensor from boot, SERIAL1 accepted while not ready, all16 voiced, busy protection and TOUCH8 rejection retained");$finish;
    end
    initial begin #250000000;$fatal(1,"16-key integration timeout keys=%h ready=%b replies=%0d",dut.touch_keys,dut.touch_ready,reply_count);end
endmodule
