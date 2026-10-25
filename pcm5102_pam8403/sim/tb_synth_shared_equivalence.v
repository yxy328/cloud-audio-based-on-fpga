`timescale 1ns/1ps
module tb_synth_shared_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg sensor_resetn=0,touch_resetn=0;
    reg [9:0] divider=0;
    wire ce=divider==1023;
    always @(posedge clk)divider<=divider+1'b1;
    reg event_valid=0,test_valid=0;
    reg [31:0] inc=23012828;
    reg [2:0] timbre=0;
    reg [129:0] adsr=0;
    reg vibrato=0,vibrato_update=0;
    reg [15:0] tuning=16384;
    reg [15:0] gates=0,physical=0;
    reg [1:0] pedal=0;
    reg [4:0] poly=16;
    reg [63:0] touch_cfg={16'd4,16'd4,16'd39321,16'd8};
    reg [223:0] steps={7{32'd23012828}};
    reg [15:0] ratio=65535;
    wire sm,sr,tm,tr,mg,rg;
    wire signed [32:0] sa,ta;
    wire signed [17:0] sb,tb;
    wire [31:0] sp,tp;
    wire signed [50:0] product;
    wire signed [15:0] sine,sc,sc_ref,tc,tc_ref;
    // Exact value the shared multiplier must hold at PITCH_MUL when tuning is not unity.
    wire [63:0] sensor_tune_full={32'd0,sensor.note_inc}*{48'd0,sensor.frame_tuning};
    wire [31:0] sensor_tune_expect=sensor_tune_full>>14;
    wire [31:0] sactive,sactive_ref;
    wire [5:0] scount,scount_ref;
    wire [15:0] tactive,tactive_ref;
    wire [4:0] tcount,tcount_ref;
    wire so,so_ref,to,to_ref,clip,clip_ref;
    integer frame_id=0,checked=0,checked_sensor=0,checked_touch=0;
    integer s_cycles=0,t_cycles=0,max_s=0,max_t=0;
    integer mul_stalls=0,rom_stalls=0,mul_run=0,rom_run=0,max_mul_run=0,max_rom_run=0;
    integer f,i,j,seed=32'h1369acf,randv,held_frames=0,tuning_holds=0;
    reg sensor_armed=0,touch_armed=0;
    reg [7:0] timbres_seen=0;

`define SENSOR_INPUTS .clk(clk),.resetn(sensor_resetn),.sample_ce(ce), \
    .event_valid(event_valid),.chord_valid(1'b0),.test_valid(test_valid), \
    .vibrato_enabled(vibrato),.vibrato_inc(32'd527766),.vibrato_depth(10'd256), \
    .vibrato_delay(16'd4),.vibrato_update(vibrato_update),.tuning_ratio(tuning), \
    .event_inc(inc),.event_timbre(timbre),.event_frames(17'd80),.event_adsr(adsr)
    tdm_synth #(.EXTENDED_TIMBRES(1),.RUNTIME_ADSR(1),.VOLUME_SHIFT(6),.SHARED_ARITH(1)) sensor(
        `SENSOR_INPUTS,.voice_active(sactive),.voice_count(scount),.sample(sc),.overrun(so),.busy(),.event_ready(),
        .shared_mul_request(sm),.shared_sine_request(sr),.shared_mul_a(sa),.shared_mul_b(sb),
        .shared_sine_phase(sp),.shared_product(product),.shared_sine(sine));
    tdm_synth_merge_reference #(.EXTENDED_TIMBRES(1),.RUNTIME_ADSR(1),.VOLUME_SHIFT(6)) sensor_ref(
        `SENSOR_INPUTS,.voice_active(sactive_ref),.voice_count(scount_ref),.sample(sc_ref),.overrun(so_ref),.busy(),.event_ready());
`undef SENSOR_INPUTS
`define TOUCH_INPUTS .clk(clk),.resetn(touch_resetn),.sample_ce(ce),.gates(gates), \
    .physical_gates(physical),.pedal_mode(pedal),.poly_limit(poly), \
    .low_steps(steps),.adsr_config(touch_cfg),.pitch_ratio(ratio)
    touch_tdm_synth #(.EXTENDED_CONTROL(1),.PEDAL_TAIL_MS(8),.DAMPER_MS(1),.SHARED_ARITH(1),.FAST_READ(1)) touch(
        `TOUCH_INPUTS,.sample(tc),.active(tactive),.voice_count(tcount),.clipped(clip),.overrun(to),
        .shared_mul_request(tm),.shared_sine_request(tr),.shared_mul_a(ta),.shared_mul_b(tb),
        .shared_sine_phase(tp),.shared_mul_grant(mg),.shared_sine_grant(rg),.shared_product(product),.shared_sine(sine));
    touch_tdm_synth_merge_reference #(.EXTENDED_CONTROL(1),.PEDAL_TAIL_MS(8),.DAMPER_MS(1)) touch_ref(
        `TOUCH_INPUTS,.sample(tc_ref),.active(tactive_ref),.voice_count(tcount_ref),.clipped(clip_ref),.overrun(to_ref));
`undef TOUCH_INPUTS
    synth_shared_arith arithmetic(.clk(clk),.sensor_mul_request(sm),.touch_mul_request(tm),
        .sensor_mul_a(sa),.touch_mul_a(ta),.sensor_mul_b(sb),.touch_mul_b(tb),
        .touch_mul_grant(mg),.product(product),.sensor_sine_request(sr),.touch_sine_request(tr),
        .sensor_sine_phase(sp),.touch_sine_phase(tp),.touch_sine_grant(rg),.sine(sine));

    always @(posedge clk)begin
        if(!sensor_resetn)sensor_armed=0;
        if(!touch_resetn)touch_armed=0;
        if(ce)begin
            if(sensor_armed)begin
                if(sensor.state!=sensor.IDLE || sensor_ref.state!=sensor_ref.IDLE ||
                   {sc,sactive,scount,so}!=={sc_ref,sactive_ref,scount_ref,so_ref} || so)
                    $fatal(1,"Sensor mismatch/deadline frame=%0d pcm=%0d/%0d",frame_id,sc,sc_ref);
                for(j=0;j<512;j=j+1)
                    if(sensor.contexts[j] !== sensor_ref.contexts[j])
                        $fatal(1,"Sensor context frame=%0d word=%0d actual=%h expected=%h",frame_id,j,sensor.contexts[j],sensor_ref.contexts[j]);
                if(s_cycles>max_s)max_s=s_cycles;
                checked_sensor=checked_sensor+1;
            end
            if(touch_armed)begin
                if(touch.state!=touch.IDLE || touch_ref.state!=touch_ref.IDLE ||
                   {tc,tactive,tcount,clip,to}!=={tc_ref,tactive_ref,tcount_ref,clip_ref,to_ref} || to)
                    $fatal(1,"Touch mismatch/deadline frame=%0d pcm=%0d/%0d active=%h/%h count=%d/%d",frame_id,tc,tc_ref,tactive,tactive_ref,tcount,tcount_ref);
                for(j=0;j<256;j=j+1)
                    if(touch.contexts[j] !== touch_ref.contexts[j])
                        $fatal(1,"Touch context frame=%0d word=%0d actual=%h expected=%h",frame_id,j,touch.contexts[j],touch_ref.contexts[j]);
                if(t_cycles>max_t)max_t=t_cycles;
                checked_touch=checked_touch+1;
                if(physical==16'hffff && poly==1)begin
                    if(tactive!=16'hffff || touch.victim_valid)$fatal(1,"Physical protection");
                    held_frames=held_frames+1;
                end
            end
            if(sensor_armed && touch_armed)checked=checked+1;
            sensor_armed=sensor_resetn && sensor.state==sensor.IDLE;
            touch_armed=touch_resetn && touch.state==touch.IDLE;
            s_cycles=0;t_cycles=0;frame_id=frame_id+1;
        end
        if(sensor_armed && (ce || sensor.state!=sensor.IDLE))s_cycles=s_cycles+1;
        if(touch_armed && (ce || touch.state!=touch.IDLE))t_cycles=t_cycles+1;
        if(tm && !mg)begin mul_stalls=mul_stalls+1;mul_run=mul_run+1;end else mul_run=0;
        if(tr && !rg)begin rom_stalls=rom_stalls+1;rom_run=rom_run+1;end else rom_run=0;
        if(mul_run>max_mul_run)max_mul_run=mul_run;
        if(rom_run>max_rom_run)max_rom_run=rom_run;
        if(mul_run>2 || rom_run>6)$fatal(1,"Arbitration wait bound");
        // Invariant: a touch grant while the sensor requests would replace the
        // product the sensor consumes on the next edge.
        if(tm && mg && sm)$fatal(1,"Sensor priority violated frame=%0d state=%0d",frame_id,sensor.state);
        // Retention check at the consumption point. The sensor keeps requesting in
        // LOOK_AUX and LOOK_AUX2, so the touch can never be granted inside that
        // window; this checks the value that actually reaches PITCH_MUL instead of
        // counting a coincidence the arbiter makes unreachable.
        if(sensor.state==sensor.PITCH_MUL && sensor.frame_tuning!=16384)begin
            if(sensor.mul_product[45:14] !== sensor_tune_expect)
                $fatal(1,"Tuning product retention frame=%0d actual=%h expected=%h",frame_id,sensor.mul_product[45:14],sensor_tune_expect);
            tuning_holds=tuning_holds+1;
        end
        if(sensor.state==sensor.EVENT_COMMIT)timbres_seen[sensor.request_timbre]=1;
    end
    task next_frame;begin @(posedge ce);@(negedge clk);end endtask
    task send_note;
        input [31:0] pitch;input [2:0] tone;
        begin @(negedge clk);inc=pitch;timbre=tone;event_valid=1;@(negedge clk);event_valid=0;end
    endtask
    initial begin
        repeat(5)@(negedge clk);sensor_resetn=1;touch_resetn=1;
        repeat(2)next_frame;
        gates=16'hffff;physical=16'hffff;
        @(negedge clk);test_valid=1;@(negedge clk);test_valid=0;
        repeat(14)next_frame;
        poly=1;repeat(6)next_frame;poly=16;
        tuning=17000;vibrato=1;
        for(i=0;i<64;i=i+1)send_note(23012828+991337*i,i%8);
        repeat(4)next_frame;
        // Burst phase above covers quota32/TEST32. Subsequent traffic covers
        // runtime ADSR, all timbres, note-off, pedal tail and arbitrary starts.
        adsr={1'b1,16'd7,16'd11,16'd13,9'd193,24'd2396745,24'd1525201,24'd1290555};
        for(f=0;f<1200;f=f+1)begin
            next_frame;
            if(f%7==0)begin randv=$random(seed);gates=randv;physical=gates;end
            if(f%43==0)begin randv=$random(seed);pedal=randv&3;if(pedal==3)pedal=0;end
            if(f%29==0)begin randv=$random(seed);poly=1<<((randv&7)%5);end
            if(f%17==0)begin
                randv=$random(seed);
                // Explicit widths avoid accidental 32-bit expression packing.
                touch_cfg[63:48]=1+(randv&15);touch_cfg[47:32]=1+((randv>>4)&15);
                touch_cfg[31:16]=39123;touch_cfg[15:0]=1+((randv>>8)&31);
                ratio=(f%34==0) ? 16'd65535 : 16'd49152;
                tuning=(f%51==0) ? 16'd16384 : 16'd17408;
                for(i=0;i<7;i=i+1)steps[i*32+:32]=23012828+f*12345;
            end
            if(f%3==0)send_note(20000000+f*997,f%8);
            if(f==300 || f==700)begin touch_resetn=0;repeat(4)@(negedge clk);touch_resetn=1;end
            if(f==500 || f==900)begin sensor_resetn=0;repeat(4)@(negedge clk);sensor_resetn=1;end
        end
        gates=0;physical=0;poly=16;pedal=2;
        repeat(450)next_frame;
        if(checked<1500 || timbres_seen!=8'hff || !mul_stalls || !rom_stalls || !held_frames || !tuning_holds)
            $fatal(1,"Missing coverage frames=%0d tones=%h mul=%0d rom=%0d held=%0d tuning=%0d",checked,timbres_seen,mul_stalls,rom_stalls,held_frames,tuning_holds);
        if(tactive!=0 || max_s>951 || max_t>982)$fatal(1,"Final silence or cycle bound");
        $display("PASS shared arithmetic exact equivalence: joint_frames=%0d sensor_frames=%0d touch_frames=%0d sensor_max=%0d touch_max=%0d mul_stalls=%0d rom_stalls=%0d max_wait=%0d/%0d tuning_hold_hits=%0d timbres=%h",
            checked,checked_sensor,checked_touch,max_s,max_t,mul_stalls,rom_stalls,max_mul_run,max_rom_run,tuning_holds,timbres_seen);
        $finish;
    end
    initial begin #60000000;$fatal(1,"Shared arithmetic equivalence timeout");end
endmodule
