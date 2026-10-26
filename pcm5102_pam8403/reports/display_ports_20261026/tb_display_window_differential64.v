`timescale 1ns/1ps
module tb_display_window_differential64;
    parameter integer LEAD=64;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,ms_tick=0,note_spawn=0;
    reg [6:0] touch_keys=0,guide_keys=0,spawn_keys=0;
    reg [15:0] spawn_delay_ms=0,all_touch_keys=0,physical_keys=0;
    reg [31:0] random=32'h67230fac;
    reg [1:0] visual_mode=0;
    reg touch_mode16=0;
    reg sample_ce=0;
    reg signed [15:0] sample=0;
    wire [13:0] actual,expected;
    wire [111:0] snapshot,reference_snapshot;
    wire ready,reference_ready,overflow,reference_overflow;
    hub75e_rhythm_display #(.LEAD_MS(LEAD),.ENABLE_AUDIO_VISUAL(1),.ENABLE_STATUS(1),.ENABLE_TAKE_STATUS(1)) dut(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.touch_keys(touch_keys),
        .guide_keys(guide_keys),.touch_mode16(touch_mode16),.all_touch_keys(all_touch_keys),
        .physical_keys(physical_keys),.ir_keys(physical_keys[7:0]),.touch_hold(random[1:0]),
        .pressure_pitch(random[2]),.recording(random[3]),.keys_ready(random[4]),
        .timbre(random[7:5]),.analog_mode(random[10:8]),.effect_mode(random[12:11]),
        .effect_wet(random[16:13]),.volume(random[21:17]),.master_gain(random[12:0]),
        .adc_sample(random[9:0]),.analog_position(random[19:10]),.analog_valid(random[20]),
        .take_flags(random[7:0]),.take_error(random[11:8]),.take_elapsed(random[23:0]),.take_count(random[10:0]),
        .visual_mode(visual_mode),.reference_ratio(random[1:0]),.reference_phase(random[3:2]),
        .scope_fsr_gain(random[31:16]),.sample_ce(sample_ce),.mixed_sample(sample),.touch0(sample),
        .touch1(-sample),.sensor_sample(sample),.guitar_sample(-sample),
        .note_ready(ready),.overflow(overflow),.visual_snapshot(snapshot),
        .hub_R1(actual[13]),.hub_G1(actual[12]),.hub_B1(actual[11]),
        .hub_R2(actual[10]),.hub_G2(actual[9]),.hub_B2(actual[8]),
        .hub_A(actual[7]),.hub_B(actual[6]),.hub_C(actual[5]),.hub_D(actual[4]),.hub_E(actual[3]),
        .hub_CK(actual[2]),.hub_ST(actual[1]),.hub_OE(actual[0]));
    hub75e_rhythm_display_before #(.LEAD_MS(LEAD),.ENABLE_AUDIO_VISUAL(1),.ENABLE_STATUS(1),.ENABLE_TAKE_STATUS(1)) reference(
        .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.touch_keys(touch_keys),
        .guide_keys(guide_keys),.touch_mode16(touch_mode16),.all_touch_keys(all_touch_keys),
        .physical_keys(physical_keys),.ir_keys(physical_keys[7:0]),.touch_hold(random[1:0]),
        .pressure_pitch(random[2]),.recording(random[3]),.keys_ready(random[4]),
        .timbre(random[7:5]),.analog_mode(random[10:8]),.effect_mode(random[12:11]),
        .effect_wet(random[16:13]),.volume(random[21:17]),.master_gain(random[12:0]),
        .adc_sample(random[9:0]),.analog_position(random[19:10]),.analog_valid(random[20]),
        .take_flags(random[7:0]),.take_error(random[11:8]),.take_elapsed(random[23:0]),.take_count(random[10:0]),
        .visual_mode(visual_mode),.reference_ratio(random[1:0]),.reference_phase(random[3:2]),
        .scope_fsr_gain(random[31:16]),.sample_ce(sample_ce),.mixed_sample(sample),.touch0(sample),
        .touch1(-sample),.sensor_sample(sample),.guitar_sample(-sample),
        .note_ready(reference_ready),.overflow(reference_overflow),.visual_snapshot(reference_snapshot),
        .hub_R1(expected[13]),.hub_G1(expected[12]),.hub_B1(expected[11]),
        .hub_R2(expected[10]),.hub_G2(expected[9]),.hub_B2(expected[8]),
        .hub_A(expected[7]),.hub_B(expected[6]),.hub_C(expected[5]),.hub_D(expected[4]),.hub_E(expected[3]),
        .hub_CK(expected[2]),.hub_ST(expected[1]),.hub_OE(expected[0]));
    integer n=0,row,p,checks=0,wraps=0,swaps=0,downs=0,ups=0;
    integer read_collisions=0,retained_collisions=0,merges=0,clear_writes=0;
    integer stops=0,frames=0;
    reg old_playing=0;
    reg [3:0] modes_seen=0;
    reg previous_q_valid=0;
    reg [6:0] previous_q0,previous_q1;
    reg collision0,collision1;
    always @(posedge clk)begin
        collision0=dut.panel_windows[0].collision;
        collision1=dut.panel_windows[1].collision;
        previous_q0=dut.panel_windows[0].q;
        previous_q1=dut.panel_windows[1].q;
        if(resetn)begin
            if(dut.window_swap)swaps=swaps+1;
            if(dut.window_down)downs=downs+1;
            if(dut.window_up)ups=ups+1;
            if(dut.scroll && dut.head_top==0)wraps=wraps+1;
            if(dut.display_boundary)frames=frames+1;
            if(!playing && old_playing)stops=stops+1;
            if(dut.head_write && dut.head_collision)merges=merges+1;
            if(dut.head_write && dut.scroll && dut.head_write_address==dut.wrapped_head)clear_writes=clear_writes+1;
            if(collision0)read_collisions=read_collisions+1;
            if(collision1)read_collisions=read_collisions+1;
            if(dut.head_write && (dut.head_write_address==dut.panel_windows[0].retained_address0 ||
                dut.head_write_address==dut.panel_windows[0].retained_address1 ||
                dut.head_write_address==dut.panel_windows[1].retained_address0 ||
                dut.head_write_address==dut.panel_windows[1].retained_address1))retained_collisions=retained_collisions+1;
        end
        old_playing=playing;
        #1;
        if(actual!==expected || snapshot!==reference_snapshot || ready!==reference_ready || overflow!==reference_overflow)
            $fatal(1,"Pins/control/snapshot mismatch lead=%0d cycle=%0d",LEAD,n);
        if(resetn)begin
            modes_seen[dut.visual_active]=1;
            for(row=0;row<64;row=row+1)
                if(dut.note_rows[row]!==reference.note_rows[row])
                    $fatal(1,"Bitmap mismatch cycle=%0d row=%0d",n,row);
            for(p=0;p<6;p=p+1)
                if(dut.panel_heads[p]!==reference.panel_heads[p])
                    $fatal(1,"Window mismatch lead=%0d cycle=%0d tap=%0d actual=%h expected=%h",LEAD,n,p,dut.panel_heads[p],reference.panel_heads[p]);
            if(collision0 && dut.panel_windows[0].q!==previous_q0)$fatal(1,"Physical read was not disabled on port0 collision");
            if(collision1 && dut.panel_windows[1].q!==previous_q1)$fatal(1,"Physical read was not disabled on port1 collision");
            if(dut.upper_notes!==reference.upper_notes || dut.lower_notes!==reference.lower_notes)
                $fatal(1,"Captured glyph mismatch cycle=%0d",n);
            checks=checks+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);
        for(n=0;n<650000;n=n+1)begin
            random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
            resetn=!(n>=600000 && n%7919<4);
            // Long uninterrupted play traverses many scan-row/window wraps.
            playing=n<560000 || n%1024<1015;
            // Sparse real ticks, no ticks, continuous ticks, then random ticks.
            ms_tick=n<150000 ? n%50000==0 : n<300000 ? 0 : n<450000 ? 1 : random[0];
            note_spawn=n%256<128 || random[1];
            spawn_keys=random[8:2];
            spawn_delay_ms=n%1024<256 ? LEAD : n%1024<512 ? 0 : random[23:8]%(LEAD+101);
            touch_keys=random[22:16];guide_keys=random[29:23];
            touch_mode16=random[30];all_touch_keys=random[31:16];physical_keys=random[15:0];
            visual_mode=(n/140000)%4;
            sample_ce=n%1024==0;sample=random[15:0];
            @(negedge clk);
        end
        if(checks<640000 || swaps<100 || wraps<100 || downs<100 || ups<100 || read_collisions<100 ||
            retained_collisions<100 || merges<100 || stops<10 || frames<4 || modes_seen!=15)
            $fatal(1,"Coverage insufficient checks=%0d swaps=%0d wraps=%0d down=%0d up=%0d read=%0d retained=%0d merge=%0d stops=%0d frames=%0d modes=%b",
                checks,swaps,wraps,downs,ups,read_collisions,retained_collisions,merges,stops,frames,modes_seen);
        $display("PASS window differential LEAD=%0d cycles=%0d scan_swap=%0d circular_wrap=%0d down/up=%0d/%0d read_collision=%0d retained_write=%0d OR_merge=%0d clear_write=%0d stops=%0d frames=%0d modes=%b",
            LEAD,checks,swaps,wraps,downs,ups,read_collisions,retained_collisions,merges,clear_writes,stops,frames,modes_seen);
        $finish;
    end
endmodule
