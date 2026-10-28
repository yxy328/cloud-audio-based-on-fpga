`timescale 1ns/1ps
// Differential test against the saved pre-optimization parallel decoder.
// Compare actual UART replies and committed control values, independently
// of the new decoder's dictionary, generator and internal timing.
// Golden source is the actual Code39 baseline, including fixed16 and score bend.
module tb_hc05_code39_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,rx=1;
    wire [1:0] tx;
    wire [511:0] reply0,reply1;
    wire [315:0] controls[0:1];
    wire [7:0] pulses[0:1];
    wire [31:0] count0,count1;
    integer pulse0[0:7],pulse1[0:7],p;
    always @(posedge clk)if(resetn)for(p=0;p<8;p=p+1)begin
        if(pulses[0][p])pulse0[p]=pulse0[p]+1;
        if(pulses[1][p])pulse1[p]=pulse1[p]+1;
    end
    hc05_keymap_code39_reference #(.CLK_HZ(1000000),.BAUD(50000),.ENABLE_DOWNLOADED_INCREMENT(0)) reference(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx[0]),.keys_ready(1'b1),
        .song_busy(1'b0),.notes_busy(1'b0),.recording(1'b0),.touch_keys(7'd0),
        .pressure_mode(1'b0),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .adc_sample(10'h2a5),.adc_timeout(1'b0),
        .audio_rec_busy(1'b0),.audio_rec_ready(1'b0),.audio_rec_overflow(1'b0),
        .take_flags(8'd0),.take_error(4'd0),.take_elapsed(24'd0),.take_duration(24'd0),.take_count(11'd0),
        .visual_requested(2'd2),.reference_ratio(2'd3),.reference_phase(2'd1),
        .visual_snapshot(112'h17E78440F7358B52507314831040),
        .note_map(controls[0][55:0]),.touch_adsr(controls[0][119:56]),
        .sensor_adsr(controls[0][249:120]),.touch_mode16(controls[0][250]),
        .touch_hold(controls[0][251]),.master_volume(controls[0][256:252]),
        .effect_mode(controls[0][258:257]),.effect_wet(controls[0][262:259]),
        .analog_mode(controls[0][265:263]),.serial_active_high(controls[0][266]),
        .analog_min(controls[0][276:267]),.analog_max(controls[0][286:277]),
        .gesture_timbre(controls[0][289:287]),.gesture_vibrato(controls[0][290]),
        .gesture_bank(controls[0][291]),.xy_ratio(controls[0][293:292]),
        .xy_phase(controls[0][295:294]),.pressure_value(controls[0][296]),
        .bend_index(controls[0][299:297]),.bend_ratio(controls[0][315:300]),
        .guitar_pluck(pulses[0][0]),.panic(pulses[0][1]),.visual_write(pulses[0][2]),
        .xy_write(pulses[0][3]),.bend_write(pulses[0][4]),.bend_reset(pulses[0][5]),
        .sensor_test32(pulses[0][6]),.pressure_write(pulses[0][7]));
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(50000),.ENABLE_DOWNLOADED_INCREMENT(0)) candidate(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx[1]),.keys_ready(1'b1),
        .song_busy(1'b0),.notes_busy(1'b0),.recording(1'b0),.touch_keys(7'd0),
        .pressure_mode(1'b0),.volume_gain(16'd65535),.pitch_ratio(16'd65535),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .adc_sample(10'h2a5),.adc_timeout(1'b0),
        .audio_rec_busy(1'b0),.audio_rec_ready(1'b0),.audio_rec_overflow(1'b0),
        .take_flags(8'd0),.take_error(4'd0),.take_elapsed(24'd0),.take_duration(24'd0),.take_count(11'd0),
        .visual_requested(2'd2),.reference_ratio(2'd3),.reference_phase(2'd1),
        .visual_snapshot(112'h17E78440F7358B52507314831040),
        .note_map(controls[1][55:0]),.touch_adsr(controls[1][119:56]),
        .sensor_adsr(controls[1][249:120]),.touch_mode16(controls[1][250]),
        .touch_hold(controls[1][251]),.master_volume(controls[1][256:252]),
        .effect_mode(controls[1][258:257]),.effect_wet(controls[1][262:259]),
        .analog_mode(controls[1][265:263]),.serial_active_high(controls[1][266]),
        .analog_min(controls[1][276:267]),.analog_max(controls[1][286:277]),
        .gesture_timbre(controls[1][289:287]),.gesture_vibrato(controls[1][290]),
        .gesture_bank(controls[1][291]),.xy_ratio(controls[1][293:292]),
        .xy_phase(controls[1][295:294]),.pressure_value(controls[1][296]),
        .bend_index(controls[1][299:297]),.bend_ratio(controls[1][315:300]),
        .guitar_pluck(pulses[1][0]),.panic(pulses[1][1]),.visual_write(pulses[1][2]),
        .xy_write(pulses[1][3]),.bend_write(pulses[1][4]),.bend_reset(pulses[1][5]),
        .sensor_test32(pulses[1][6]),.pressure_write(pulses[1][7]));
    hc05_equivalence_monitor old_monitor(clk,tx[0],reply0,count0);
    hc05_equivalence_monitor new_monitor(clk,tx[1],reply1,count1);
    task send_byte;
        input [7:0] value;integer bitno;
        begin
            @(negedge clk);rx=0;repeat(20)@(negedge clk);
            for(bitno=0;bitno<8;bitno=bitno+1)begin rx=value[bitno];repeat(20)@(negedge clk);end
            rx=1;repeat(20)@(negedge clk);
        end
    endtask
    integer checks=0;
    reg [55:0] expected_new_map={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
    task transact;
        input [527:0] text;input integer length;
        integer n,target,waited;
        begin: legacy_transaction
            // New commands and HOLD mode 2 are covered by tb_top_pedal, not this frozen reference.
            if(text=="HOLD,?" || text=="HOLD,2" || text=="CTRL2?" ||
               (length>=6 && (text>>((length-5)*8))=="POLY,"))disable legacy_transaction;
            target=count0+1;
            for(n=length-1;n>=0;n=n-1)send_byte(text[n*8 +: 8]);
            send_byte(10);waited=0;
            while((count0<target || count1<target) && waited<20000)begin @(negedge clk);waited=waited+1;end
            if(count0!=target || count1!=target)$fatal(1,"reply timeout for '%0s'",text);
            if(text=="MAP_RESET")expected_new_map={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
            if(text=="MAP,1,72")expected_new_map[7:0]=72;
            if(reply0!==reply1)$fatal(1,"Code39 reply mismatch for '%0s': '%0s' vs '%0s'",text,reply0,reply1);
            if(controls[0]!==controls[1] || controls[1][55:0]!==expected_new_map)$fatal(1,"committed controls differ for '%0s'",text);
            for(n=0;n<8;n=n+1)if(pulse0[n]!=pulse1[n])$fatal(1,"pulse count differs for '%0s'",text);
            checks=checks+1;
        end
    endtask
    reg [527:0] text,mutated;
    reg [31:0] random_state=32'h10a53c71;
    reg [7:0] random_byte;
    integer i,j,length,random_length;
    initial begin
        for(p=0;p<8;p=p+1)begin pulse0[p]=0;pulse1[p]=0;end
        repeat(3)@(negedge clk);resetn=1;
        for(i=0;i<56;i=i+1)begin
            case(i)
                0:begin text="PING";length=4;end
                1:begin text="CTRL?";length=5;end
                2:begin text="SERIAL?";length=7;end
                3:begin text="SERIAL,1";length=8;end
                4:begin text="SERIAL,0";length=8;end
                5:begin text="CAL?";length=4;end
                6:begin text="CAL,0,1023";length=10;end
                7:begin text="ADC?";length=4;end
                8:begin text="VIS,3";length=5;end
                9:begin text="VIS?";length=4;end
                10:begin text="VIZ?";length=4;end
                11:begin text="XY,3,2";length=6;end
                12:begin text="XY,4,0";length=6;end
                13:begin text="TOUCH,16";length=8;end
                14:begin text="TOUCH,8";length=7;end
                15:begin text="EFFECT,2,8";length=10;end
                16:begin text="HOLD,1";length=6;end
                17:begin text="HOLD,0";length=6;end
                18:begin text="VOLUME,16";length=9;end
                19:begin text="ANALOG,4";length=8;end
                20:begin text="ANALOG,0";length=8;end
                21:begin text="PRESSURE,1";length=10;end
                22:begin text="BEND,1,32768";length=12;end
                23:begin text="BEND_RESET";length=10;end
                24:begin text="ADSR,TOUCH,1000,1000,100,1000";length=29;end
                25:begin text="ADSR,SENSOR,0,0,0,0";length=19;end
                26:begin text="ADSR_RESET,TOUCH";length=16;end
                27:begin text="ADSR_RESET,SENSOR";length=17;end
                28:begin text="TEST32";length=6;end
                29:begin text="GUITAR";length=6;end
                30:begin text="TONE,7";length=6;end
                31:begin text="VIBRATO,1";length=9;end
                32:begin text="BANK,1";length=6;end
                33:begin text="MAP?";length=4;end
                34:begin text="MAP,1,72";length=8;end
                35:begin text="MAP_RESET";length=9;end
                36:begin text="PLAY";length=4;end
                37:begin text="AUDITION";length=8;end
                38:begin text="STOP";length=4;end
                39:begin text="PANIC";length=5;end
                40:begin text="AREC?";length=5;end
                41:begin text="AREC_START,65535";length=16;end
                42:begin text="AREC_STOP";length=9;end
                43:begin text="AREC_ABORT";length=10;end
                44:begin text="TAKE?";length=5;end
                45:begin text="TAKE_SAVE";length=9;end
                46:begin text="SONG_BEGIN,2";length=12;end
                47:begin text="SONG_NOTE,0,60,12";length=17;end
                48:begin text="SONG_CHORD,1,17,12";length=18;end
                49:begin text="SONG_END";length=8;end
                50:begin text="ADSR,TOUCH,1,,3,4";length=17;end
                51:begin text="VOLUME,65536";length=12;end
                52:begin text=" MAP?";length=5;end
                53:begin text="PINGx";length=5;end
                54:begin text="ping";length=4;end
                55:begin text="REC_STOP";length=8;end
            endcase
            transact(text,length);
            // Mutate every character of the command name. Arguments and
            // line boundaries remain intact, stressing exact prefix checks.
            for(j=length-1;j>=0;j=j-1)begin
                if(text[j*8 +: 8]==",")j=-1;
                else begin
                    mutated=text;mutated[j*8 +: 8]="x";
                    transact(mutated,length);
                end
            end
        end
        for(i=0;i<128;i=i+1)begin
            text=0;random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            random_length=1+random_state%64;
            for(j=0;j<random_length;j=j+1)begin
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                random_byte=32+random_state%95;text={text[519:0],random_byte};
            end
            transact(text,random_length);
        end
        text={66{"A"}};transact(text,65);
        $display("PASS HC05 decoder differential: %0d UART transactions, exact replies/control values/pulses, mutated commands and random lines",checks);
        $finish;
    end
    initial begin #300000000;$fatal(1,"HC05 differential timeout");end
endmodule

module hc05_equivalence_monitor(input wire clk,tx,output reg [511:0] last_reply=0,output reg [31:0] count=0);
    reg [511:0] incoming=0;
    reg [7:0] data;
    integer bitno;
    initial forever begin
        @(negedge tx);repeat(10)@(posedge clk);
        if(tx!==0)$fatal(1,"UART start bit");
        for(bitno=0;bitno<8;bitno=bitno+1)begin repeat(20)@(posedge clk);data[bitno]=tx;end
        repeat(20)@(posedge clk);if(tx!==1)$fatal(1,"UART stop bit");
        incoming={incoming[503:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;count=count+1;end
    end
endmodule
