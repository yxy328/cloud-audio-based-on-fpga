`timescale 1ns/1ps
// Real 50MHz/I2S timing; UART divisor accelerated for this joint audio test.
// tb_uart_8n1 also runs independently with the production 9600 divisor.
module tb_top_hc05_map;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg rx=1,s1=0,s2=0;
    reg [7:0] pads=0;
    wire tx,bck,lrck,din;
    reg [255:0] replies[0:31],incoming=0;
    reg [7:0] decoded;
    integer reply_count=0,expected_count=0,bit_index,first,n;
    real g4,c4,c5,wrong;
    reg [31:0] previous_phase,expected_phase;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(3000),.KEY_CONFIRM_CYCLES(1000),
        .TOUCH_MODE_DEBOUNCE_MS(2),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .ADSR_RELEASE_SAMPLES(32),.TOUCH_ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(s1),.key_s2(s2),.touch_out(pads),.hc05_rx(rx),.hc05_tx(tx),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl());
    i2s_pcm_monitor monitor(.bck(bck),.lrck(lrck),.din(din));
    // UART and pressure changes must never reset or skip the DDS accumulator.
    always @(posedge clk) if(dut.resetn && dut.frame_ce) begin
        previous_phase=dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase;
        expected_phase=previous_phase+dut.touch_phase_increments[31:0];#1;
        if(dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase!==expected_phase)
            $fatal(1,"UART mapping disturbed DDS phase continuity");
    end
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"Top TX start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(BIT_TICKS) @(posedge clk);decoded[bit_index]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);if(tx!==1) $fatal(1,"Top TX stop bit");
        incoming={incoming[247:0],decoded};
        if(decoded==10) begin replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;end
    end
    task transact;
        input [255:0] message;
        input integer length;
        input [255:0] expected;
        integer j,b;
        begin
            for(j=length-1;j>=0;j=j-1) begin
                @(negedge clk);rx=0;repeat(BIT_TICKS) @(negedge clk);
                for(b=0;b<8;b=b+1) begin rx=message[j*8+b];repeat(BIT_TICKS) @(negedge clk);end
                rx=1;repeat(BIT_TICKS) @(negedge clk);
            end
            wait(reply_count>expected_count);
            if(replies[expected_count]!==expected)
                $fatal(1,"Top reply expected %0s got %0s",expected,replies[expected_count]);
            expected_count=expected_count+1;
        end
    endtask
    task measure;
        input real hz;
        output real result;
        real co,si,w,ws,angle;
        begin
            first=monitor.pcm_count;wait(monitor.pcm_count>=first+512);#1;
            co=0;si=0;ws=0;
            for(n=0;n<512;n=n+1) begin
                w=0.5-0.5*$cos(6.283185307179586*n/511.0);
                angle=6.283185307179586*hz*n/48828.125;
                co=co+w*monitor.pcm[first+n]*$cos(angle);
                si=si+w*monitor.pcm[first+n]*$sin(angle);ws=ws+w;
            end
            result=2*$sqrt(co*co+si*si)/ws;
        end
    endtask
    task release_key;
        begin pads=0;wait(dut.touch_keys[6:0]==0);wait(dut.touch_active[6:0]==0);#1000;end
    endtask
    initial begin
        #7000000;
        if(!dut.touch_ready || dut.touch_note_map[7:0]!==60) $fatal(1,"Top default map/startup");
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        transact({"MAP,1,67",8'd13,"\n"},10,{"OK,MAP,1,67",8'd13,"\n"});
        pads=1;wait(dut.touch_keys[0]);#1000000;
        measure(391.9954359817493,g4);
        if(g4<1170 || g4>1280 || dut.touch_phase_increments[31:0]!==34480283)
            $fatal(1,"Remapped key 1 did not sound G4: %f",g4);
        $display("PASS [top remap tone]: G4=%0.2f, key 1 step=%0d",g4,dut.touch_phase_increments[31:0]);
        transact("MAP,1,60\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("MAP_RESET\n",10,{"ERR,BUSY",8'd13,"\n"});
        if(dut.touch_note_map[7:0]!==67) $fatal(1,"Held note was remapped");
        release_key;
        // Raw synchronized pads protect the 2ms debounce window too.
        force dut.touch_keys_raw[0]=1'b1;
        transact("MAP,1,60\n",9,{"ERR,BUSY",8'd13,"\n"});release dut.touch_keys_raw[0];
        s1=1;#100000;s1=0;wait(dut.song_playing);
        transact("MAP,1,60\n",9,{"ERR,BUSY",8'd13,"\n"});
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        s1=1;#100000;s1=0;wait(!dut.song_playing);wait(dut.song_active==0);
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,"\n"});
        pads=1;wait(dut.touch_keys[0]);#1000000;measure(261.6255653005986,c4);
        if(c4<1170 || c4>1280 || dut.touch_phase_increments[31:0]!==23012828)
            $fatal(1,"Reset key 1 did not sound C4: %f",c4);
        $display("PASS [top reset tone]: C4=%0.2f",c4);
        release_key;
        transact("MAP,1,72\n",9,{"OK,MAP,1,72",8'd13,"\n"});
        pads=1;wait(dut.touch_keys[0]);#1000000;measure(523.2511306011972,c5);
        if(c5<1170 || c5>1280) $fatal(1,"C5 upper bound missing");
        pads=8'h81;wait(dut.fsr_pitch_mode);pads=1;wait(!dut.touch_keys[7]);
        dut.u_fsr_adc.adc_inst.sim_value={3'd0,10'd1023,1'b0};
        wait(dut.fsr_pitch_ratio==32768);#1000000;measure(261.6255653005986,wrong);
        if(wrong<1170 || wrong>1280 || dut.touch_phase_increments[31:0]!==23012828)
            $fatal(1,"Pressure did not scale remapped C5 to C4");
        transact("PING\n",5,{"PONG",8'd13,"\n"});
        if(dut.touch_note_gates[7]!==0) $fatal(1,"Mode key 8 started a note");
        $display("PASS [top HC05, real I2S/accelerated UART]: key 1 G4=%0.2f, reset C4=%0.2f, upper C5=%0.2f, pressure octave C4=%0.2f; busy protection for held/raw notes/song, PING while playing, DDS phase continuity and continuous I2S; %0d stereo pairs",g4,c4,c5,wrong,monitor.pair_count);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #1000000000;$fatal(1,"Top HC05 mapping timeout");end
endmodule
