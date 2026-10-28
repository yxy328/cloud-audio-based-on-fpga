`timescale 1ns/1ps
module tb_control12;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [15:0] pads=0;
    wire tx,scl,sdo,bck,lrck,din,r1,g1,b1,r2,g2,b2,ha,hb,hc,hd,he,hck,lat,oe;
    top #(.CONTROL_KEYS(12),.HC05_BAUD(500000),.GUIDE_LEAD_MS(60),.FSR_ENABLE(0),
        .TOUCH_STARTUP_US(100),.TOUCH_SERIAL_HALF_CYCLES(50),.TOUCH_SERIAL_GAP_CYCLES(500),
        .TOUCH_SERIAL_QUIET_CYCLES(50),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.ir_beam(8'hff),
        .touch_sdo(sdo),.hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .touch_scl(scl),.hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(ha),.hub_B(hb),.hub_C(hc),.hub_D(hd),.hub_E(he),.hub_CK(hck),.hub_ST(lat),.hub_OE(oe));
    // Accelerate only score milliseconds; audio clock/frame/serial input stay physical.
    defparam dut.u_keymap.u_download.CLK_HZ=500000;
    ttp229_model #(.TIMEOUT_NS(5000)) chip(.rst_n(dut.resetn),.scl(scl),.connected(1'b1),.dv(1'b0),
        .stuck_low(1'b0),.keys(pads),.sdo(sdo));
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24576)) pcm(.bck(bck),.lrck(lrck),.din(din));
    reg [511:0] incoming=0,replies[0:127];
    reg [7:0] byte_value;
    integer reply_count=0,next_reply=0,bit_number;
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        if(tx!==0)$fatal(1,"UART start");
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
            repeat(100)@(posedge clk);byte_value[bit_number]=tx;
        end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"UART stop");
        incoming={incoming[503:0],byte_value};
        if(byte_value==10)begin replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;end
    end
    task send;
        input [511:0] message;input integer length;input [511:0] expected;
        integer j,b,timeout;
        begin
            for(j=length-1;j>=0;j=j-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=message[j*8+b];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            timeout=0;while(reply_count<=next_reply && timeout<100000)begin @(negedge clk);timeout=timeout+1;end
            if(reply_count<=next_reply || replies[next_reply]!==expected)
                $fatal(1,"reply %0d for %0s expected %0s got %0s",next_reply,message,expected,replies[next_reply]);
            $display("control12 reply %0d: %0s",next_reply,message);next_reply=next_reply+1;
        end
    endtask
    task frames;input integer n;integer j;begin
        for(j=0;j<n;j=j+1)begin @(posedge dut.frame_ce);@(negedge clk);end
        repeat(100)@(negedge clk);
    end endtask
    reg [31:0] base[0:11];reg [15:0] ratios[0:11];reg [63:0] product_value;
    integer k,checks=0;
    task pitches;
        begin
            for(k=0;k<12;k=k+1)begin
                product_value=base[k];product_value=product_value*ratios[k];
                if(dut.touch_phase_increments[k*32+:32]!==product_value[45:14])
                    $fatal(1,"key %0d pitch expected %0d got %0d",k+1,product_value[45:14],dut.touch_phase_increments[k*32+:32]);
                checks=checks+1;
            end
        end
    endtask
    integer columns=0,latches=0;reg [11:0] cyan_lanes=0;
    always @(posedge hck)if(dut.resetn)begin
        if(columns>=64)$fatal(1,"Panel width");
        if(columns>=9 && columns<56 && columns[1:0]==1 && !r1 && g1 && b1)
            cyan_lanes[(columns-8)/4]=1;
        columns=columns+1;
    end
    always @(posedge lat)if(dut.resetn)begin
        if(columns!=64 || oe!==1)$fatal(1,"Panel latch");columns=0;latches=latches+1;
    end
    always @(negedge clk)if(dut.resetn)begin
        if(dut.bend_write && (dut.bend_index>=12 || dut.bend_ratio<dut.bend_min || dut.bend_ratio>dut.bend_max))$fatal(1,"HC05 violated trusted pitch write contract");
        if(dut.u_touch_synth.overrun || dut.u_output_mix.clipped)$fatal(1,"Audio deadline/headroom");
    end
    reg [383:0] before_phase;reg [31:0] delta;
    initial begin
        base[0]=23012828;base[1]=24381242;base[2]=25831026;base[3]=27367019;
        base[4]=28994347;base[5]=30718440;base[6]=32545054;base[7]=34480283;
        base[8]=36530588;base[9]=38702809;base[10]=41004198;base[11]=43442435;
        for(k=0;k<12;k=k+1)ratios[k]=16384;
        wait(dut.touch_ready);frames(3);
        send("MAP?\015",5,"MAP,60,61,62,63,64,65,66,67,68,69,70,71\015\012");
        pitches;
        send("MAP,12,72\015",10,"OK\015\012");frames(2);base[11]=46025656;pitches;
        send("MAP,13,60\015",10,"ERR,KEY\015\012");
        send("MAP,0,60\015",9,"ERR,KEY\015\012");
        send("MAP,12,73\015",10,"ERR,NOTE\015\012");
        send("MAP,12,60,61\015",13,"ERR,CMD\015\012");
        send("MAP_RESET\015",10,"OK,MAP_RESET\015\012");base[11]=43442435;frames(3);pitches;
        send("PITCH,8192,32768,65535,16384\015",29,"OK\015\012");
        send("BEND,7,8192\015",12,"OK\015\012");ratios[6]=8192;
        send("BEND,8,24576\015",13,"OK\015\012");ratios[7]=24576;
        send("BEND,12,32768\015",14,"OK\015\012");ratios[11]=32768;
        send("BEND,13,16384\015",14,"ERR,RANGE\015\012");
        send("BEND,12,8191\015",13,"ERR,RANGE\015\012");
        send("BEND,12,32769\015",14,"ERR,RANGE\015\012");frames(100);pitches;
        pads=16'hffff;wait(dut.touch_note_gates==16'hffff);frames(12);
        if(dut.touch_voice_count!=16)$fatal(1,"Lost high keys or voices");
        before_phase=dut.u_touch_synth.phases[383:0];frames(1);
        for(k=0;k<12;k=k+1)begin
            delta=dut.u_touch_synth.phases[k*32+:32]-before_phase[k*32+:32];
            if(delta!==dut.touch_phase_increments[k*32+:32])$fatal(1,"DDS key %0d phase continuity",k+1);
        end
        send("MAP,12,72\015",10,"ERR,BUSY\015\012");
        pads=0;wait(dut.touch_note_gates==0);frames(50);
        send("SONG_BEGIN,1\015",13,"OK\015\012");
        send("SONG_CHORD,0,4095,1000,24576\015",29,"OK\015\012");
        send("SONG_END\015",9,"OK\015\012");
        send("AUDITION\015",9,"OK\015\012");
        wait(dut.song_guide_keys==12'hfff);frames(100);
        for(k=0;k<12;k=k+1)ratios[k]=24576;
        pitches;
        if(dut.touch_note_gates[11:0]!=12'hfff || cyan_lanes!=12'hfff)$fatal(1,"12 score lanes/audio missing %h",cyan_lanes);
        send("STOP\015",5,"OK\015\012");frames(100);
        for(k=0;k<12;k=k+1)ratios[k]=16384;
        ratios[6]=8192;ratios[7]=24576;ratios[11]=32768;pitches;
        send("SONG_BEGIN,1\015",13,"OK\015\012");
        send("SONG_NOTE,0,72,100\015",19,"OK\015\012");send("SONG_END\015",9,"ERR,MAP\015\012");
        send("BEND_RESET\015",11,"OK\015\012");frames(100);
        for(k=0;k<12;k=k+1)ratios[k]=16384;pitches;
        $display("PASS control12 UART, twelve exact pitches, 16 voices, independent bend, score scope, STOP/manual restoration: %0d pitch checks, %0d replies, %0d panel rows",checks,next_reply,latches);
        $finish;
    end
    initial begin #60000000;$fatal(1,"control12 timeout");end
endmodule
