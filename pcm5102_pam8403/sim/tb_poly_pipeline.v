`timescale 1ns/1ps
// Accelerated sample enable (64 master clocks): still longer than the ADSR
// 16-clock slope preparation. The real 1024-clock period is tested in tb_top.
module tb_poly_pipeline;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0;
    reg [5:0] sample_counter=0;
    always @(posedge clk) begin
        if(!resetn) sample_counter<=0;
        else sample_counter<=sample_counter+1'b1;
    end
    wire sample_ce=sample_counter==63;
    reg [3:0] gates=0,reference_gates=0;
    reg [127:0] increments={32'd77405619,32'd57988693,32'd46025656,32'd38702809};
    wire [127:0] reference_increments={32'd77405619,32'd57988693,32'd46025656,32'd38702809};
    wire signed [15:0] mixed,reference_mixed;
    wire [63:0] samples,gains,reference_samples,reference_gains;
    wire [11:0] states,reference_states;
    wire [3:0] active,reference_active;
    wire clipped;
    poly_synth #(.PIPELINE_OSCILLATOR(1),.ATTACK_SAMPLES(8),.DECAY_SAMPLES(16),.RELEASE_SAMPLES(64)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.gates(gates),
        .phase_increments(increments),.sample(mixed),.voice_samples(samples),
        .envelope_gains(gains),.envelope_states(states),.active(active),.clipped(clipped));
    poly_synth #(.ATTACK_SAMPLES(8),.DECAY_SAMPLES(16),.RELEASE_SAMPLES(64)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.gates(reference_gates),
        .phase_increments(reference_increments),.sample(reference_mixed),
        .voice_samples(reference_samples),.envelope_gains(reference_gains),
        .envelope_states(reference_states),.active(reference_active),.clipped());
    reg [31:0] phases[0:3];
    integer previous_voice[0:3],expected_voice[0:3];
    integer v,sum,oscillator,product,checks=0,noninterference_checks=0;
    integer saved_gain,j;
    real sine_value;
    reg [3:0] compare_mask=4'b1101;
    always @(posedge clk) begin
        if(!resetn) begin
            for(v=0;v<4;v=v+1) begin phases[v]=0;previous_voice[v]=0;end
        end else if(sample_ce) begin
            sum=0;
            for(v=0;v<4;v=v+1) begin
                sum=sum+previous_voice[v];
                sine_value=32767.0*$sin(6.283185307179586*(phases[v]>>22)/1024.0);
                oscillator=$rtoi(sine_value+((sine_value<0)?-0.5:0.5));
                product=oscillator*gains[v*16 +:16];
                // Integer oracle matches documented Q0.16 and 1/16 gain.
                expected_voice[v]=product/1048576;
                if(product<0 && product%1048576!=0) expected_voice[v]=expected_voice[v]-1;
                phases[v]=phases[v]+increments[v*32 +:32];
            end
            #1;
            if(mixed!=sum || clipped) $fatal(1,"Four-voice mix differs from independent mathematical sum");
            for(v=0;v<4;v=v+1) begin
                if($signed(samples[v*16 +:16])!=expected_voice[v])
                    $fatal(1,"Voice %0d sample/pitch/Q0.16 pipeline error",v);
                previous_voice[v]=expected_voice[v];
                if(compare_mask[v]) begin
                    if(samples[v*16 +:16]!=reference_samples[v*16 +:16] ||
                       gains[v*16 +:16]!=reference_gains[v*16 +:16] ||
                       states[v*3 +:3]!=reference_states[v*3 +:3] || active[v]!=reference_active[v])
                        $fatal(1,"Voice %0d changed when another voice was released/retuned",v);
                    noninterference_checks=noninterference_checks+1;
                end
            end
            checks=checks+1;
        end
    end
    task run_samples;
        input integer count;
        integer n;
        begin
            for(n=0;n<count;n=n+1) begin
                @(negedge clk);
                while(!sample_ce) @(negedge clk);
                @(posedge clk);#2;
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        run_samples(5);
        if(mixed!=0 || active!=0) $fatal(1,"Idle voices not silent");
        @(negedge clk);gates=15;reference_gates=15;
        run_samples(3000);
        if(active!=15 || gains!={4{16'd39321}}) $fatal(1,"Four independent sustain voices missing");
        @(negedge clk);increments[63:32]=32'd51662052;
        run_samples(800);
        @(negedge clk);gates[1]=0;
        run_samples(20);
        if(!active[1] || gains[31:16]==0 || gains[31:16]>=39321)
            $fatal(1,"Selected voice tail cut off or failed to fade");
        saved_gain=gains[31:16];
        @(negedge clk);gates[1]=1;
        repeat(2) @(posedge clk);#1;
        if(gains[31:16]!=saved_gain) $fatal(1,"Retrigger reset envelope instead of remaining continuous");
        run_samples(100);
        @(negedge clk);gates[1]=0;
        run_samples(80);
        if(active!=4'b1101 || samples[31:16]!=0 || gains[31:16]!=0)
            $fatal(1,"Only released voice should reach idle/zero");
        @(negedge clk);gates[1]=1;
        run_samples(100);
        if(active!=15 || gains!={4{16'd39321}}) $fatal(1,"Restored voice did not sustain");
        compare_mask=0;
        for(j=0;j<4;j=j+1) begin
            @(negedge clk);gates=15 ^ (1<<j);
            run_samples(80);
            if(active!=gates || gains[j*16 +:16]!=0 || samples[j*16 +:16]!=0)
                $fatal(1,"Independent gate mapping failed for voice %0d",j);
            @(negedge clk);gates=15;
            run_samples(80);
        end
        @(negedge clk);gates=0;
        run_samples(80);
        if(mixed!=0 || active!=0 || samples!=0) $fatal(1,"Final polyphonic silence");
        resetn=0;repeat(3) @(negedge clk);
        if(mixed!=0 || samples!=0 || gains!=0 || active!=0) $fatal(1,"Polyphonic reset");
        $display("PASS [polyphony]: %0d mathematical sample/mix frames; %0d unchanged-voice comparisons; four sustain voices, isolated pitch change/release, continuous retrigger, all four gate mappings, final silence and reset",checks,noninterference_checks);
        $finish;
    end
    initial begin #20000000;$fatal(1,"Polyphony test timeout");end
endmodule
