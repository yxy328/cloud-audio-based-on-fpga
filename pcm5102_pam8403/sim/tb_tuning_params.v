`timescale 1ns/1ps
module tb_tuning_params;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,test_valid=0;
    reg [9:0] divider=0;
    always @(posedge clk)divider<=divider+1'b1;
    wire sample_ce=divider==0;
    reg [15:0] tuning_ratio=16384;
    localparam [223:0] BASE={32'd32545054,32'd30718440,32'd28994347,32'd27367019,32'd25831026,32'd24381242,32'd23012828};
    wire [255:0] steps;
    wire touch_overrun,sensor_overrun,sensor_busy;
    wire [31:0] sensor_active;
    wire [5:0] sensor_count;
    fsr_pitch_scaler #(.PER_VOICE_BEND(1)) scaler(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.pitch_ratio(16'd65535),.note_increments(BASE),
        .bend_write(1'b0),.bend_reset(1'b0),.bend_index(3'd0),.bend_ratio(16'd16384),
        .bend_min(16'd8192),.bend_max(16'd32768),.bend_slew(16'd4096),.phase_increments(steps));
    touch_tdm_synth touch(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.gates(16'hffff),.physical_gates(16'hffff),
        .pedal_mode(2'd0),.poly_limit(5'd16),.low_steps(steps[223:0]),.adsr_config({16'd4,16'd4,16'd32768,16'd4}),
        .pitch_ratio(16'd65535),.overrun(touch_overrun));
    tdm_synth #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1),.PRESET_FRAMES(1)) sensor(.tuning_ratio(tuning_ratio),
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.event_valid(1'b0),.chord_valid(1'b0),.test_valid(test_valid),
        .vibrato_enabled(1'b0),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),
        .event_inc(32'd0),.event_timbre(3'd0),.event_frames(17'd0),.event_adsr(130'd0),
        .voice_active(sensor_active),.voice_count(sensor_count),.overrun(sensor_overrun),.busy(sensor_busy));
    integer frames=0,cycles=0,max_cycles=0,checks=0,i,j;
    reg [31:0] before[0:15],delta;
    reg [63:0] expected;
    always @(negedge clk)if(resetn)begin
        if(sample_ce)begin frames=frames+1;cycles=0;end
        else if(sensor_busy)begin cycles=cycles+1;if(cycles>max_cycles)max_cycles=cycles;end
        if(touch_overrun || sensor_overrun)$fatal(1,"Tuning exceeded audio frame deadline: touch=%0d sensor=%0d sensor_max=%0d touch_state=%0d sensor_state=%0d",touch_overrun,sensor_overrun,max_cycles,touch.state,sensor.state);
    end
    reg [63:0] sensor_expected;
    always @(posedge clk)if(resetn && sensor.state==sensor.BODY_MUL)begin
        sensor_expected=sensor.note_inc;sensor_expected=(sensor_expected*sensor.frame_tuning)>>14;
        #1;if(sensor.phase_step!==sensor_expected[31:0])$fatal(1,"Sensor tuned phase increment mismatch");
        checks=checks+1;
    end
    task wait_frames;
        input integer count;integer finish;
        begin finish=frames+count;wait(frames>=finish);@(negedge clk);end
    endtask
    function [31:0] note_step;
        input integer key;integer midi;real hz;
        begin
            if(key<12)midi=60+key;
            else case(key)12:midi=72;13:midi=74;14:midi=76;default:midi=77;endcase
            hz=440*$pow(2.0,(midi-69)/12.0);note_step=$rtoi(hz*4294967296.0/48828.125+0.5);
        end
    endfunction
    task verify_tuning;
        input [15:0] ratio;
        begin
            tuning_ratio=ratio;wait_frames(4);
            for(j=0;j<8;j=j+1)begin
                for(i=0;i<16;i=i+1)before[i]={touch.contexts[i*16+1],touch.contexts[i*16]};
                wait_frames(1);
                for(i=0;i<16;i=i+1)begin
                    delta={touch.contexts[i*16+1],touch.contexts[i*16]}-before[i];
                    expected=note_step(i);
                    if(delta>expected+1 || delta+1<expected)$fatal(1,"Touch K%0d tuning %0d expected %0d got %0d",i+1,ratio,expected,delta);
                end
            end
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;repeat(600)@(negedge clk);
        test_valid=1;@(negedge clk);test_valid=0;wait_frames(8);
        if(sensor_count!=32)$fatal(1,"Did not activate all 32 sensor voices");
        verify_tuning(7727);verify_tuning(19573);verify_tuning(34704);
        if(max_cycles>=1024 || checks<1000)$fatal(1,"Insufficient tuning coverage or missed deadline");
        $display("PASS tuning scope: 32 sensor voices retuned, all 16 touch voices fixed, -12/A415, +3/A442, +12/A466, <=1 DDS tick error; sensor max busy %0d clocks, %0d increments",max_cycles,checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"Tuning timeout");end
endmodule
