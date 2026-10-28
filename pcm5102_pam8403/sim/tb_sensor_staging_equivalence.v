`timescale 1ns/1ps
module tb_sensor_staging_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,frame_ce=0,sensor_ready=1,gesture_valid=0,dir_evaluated=1,ir_note_valid=0,test32=0;
    reg [2:0] start_dir=1,end_dir=2,ir_note_index=0,control_timbre=0;
    reg control_vibrato=0,control_bank=0;reg [129:0] adsr_config=0;
    wire signed [15:0] sample_a,sample_b;
    wire [31:0] active_a,active_b;wire [5:0] count_a,count_b;wire overrun_a,overrun_b;
    sensor_poly_audio dut(.clk(clk),.resetn(resetn),.frame_ce(frame_ce),.sensor_ready(sensor_ready),
        .gesture_valid(gesture_valid),.dir_evaluated(dir_evaluated),.start_dir(start_dir),.end_dir(end_dir),
        .ir_note_valid(ir_note_valid),.ir_note_index(ir_note_index),.control_timbre(control_timbre),
        .control_vibrato(control_vibrato),.control_bank(control_bank),.test32(test32),.adsr_config(adsr_config),
        .vibrato_inc(32'd0),.vibrato_depth(10'd0),.vibrato_delay(16'd0),.vibrato_update(1'b0),.tuning_ratio(16'd16384),
        .audio_sample(sample_a),.voice_active(active_a),.voice_count(count_a),.overrun(overrun_a));
    sensor_staging_reference ref_dut(.clk(clk),.resetn(resetn),.frame_ce(frame_ce),.sensor_ready(sensor_ready),
        .gesture_valid(gesture_valid),.dir_evaluated(dir_evaluated),.start_dir(start_dir),.end_dir(end_dir),
        .ir_note_valid(ir_note_valid),.ir_note_index(ir_note_index),.control_timbre(control_timbre),
        .control_vibrato(control_vibrato),.control_bank(control_bank),.test32(test32),.adsr_config(adsr_config),
        .vibrato_inc(32'd0),.vibrato_depth(10'd0),.vibrato_delay(16'd0),.vibrato_update(1'b0),.tuning_ratio(16'd16384),
        .audio_sample(sample_b),.voice_active(active_b),.voice_count(count_b),.overrun(overrun_b));
    integer cycle,seed=831147,value,events=0,collisions=0,full_cycles=0;
    always @(posedge clk)if(resetn)begin
        if({dut.pop,dut.send_test,dut.queued,overrun_a}!=={ref_dut.pop,ref_dut.send_test,ref_dut.queued,overrun_b})$fatal(1,"queue control changed cycle %0d",cycle);
        if(dut.pop)begin
            events=events+1;
            if(dut.next_event!==ref_dut.next_event)$fatal(1,"atomic snapshot changed cycle %0d got %h expected %h",cycle,dut.next_event,ref_dut.next_event);
        end
        if(dut.config_collision)collisions=collisions+1;if(dut.queued==4)full_cycles=full_cycles+1;
        #1;if({sample_a,active_a,count_a}!=={sample_b,active_b,count_b})$fatal(1,"audio changed cycle %0d",cycle);
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        for(cycle=0;cycle<150000;cycle=cycle+1)begin
            @(negedge clk);value=$random(seed);frame_ce=cycle%1024==0;
            // Dense two-producer bursts, isolated events, stalls, wraps and
            // changing every configuration bit expose stale/forwarded data.
            ir_note_valid=cycle<500 || (value&127)==0;
            gesture_valid=cycle<500 || (value&255)==1;
            control_timbre=value[6:4];control_bank=value[10];ir_note_index=value[13:11];
            adsr_config={1'b1,16'd2,16'd7,16'd3,9'd200,24'd8388608,24'd2396745,24'd5592405};
            if(cycle%3==0)adsr_config[72:0]={value[8:0],32'h76543210,32'h13579bdf};
            test32=cycle%10001==9999;
            if(cycle==70000)resetn=0;else resetn=1;
        end
        if(events<200 || collisions<100 || full_cycles<100)$fatal(1,"insufficient staging coverage %0d/%0d/%0d",events,collisions,full_cycles);
        $display("PASS sensor staging exact equivalence: 150000 cycles, %0d event snapshots, %0d read/write forwards, %0d full cycles, audio/queue/overflow/reset",events,collisions,full_cycles);$finish;
    end
endmodule
