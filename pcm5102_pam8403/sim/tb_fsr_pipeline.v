`timescale 1ns/1ps
// Production configuration with an ADC behavioral conversion model.
module tb_fsr_pipeline;
    reg clk=0;always #10 clk=~clk;
    wire bck,lrck,din;
    top dut(.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'h00),
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl());
    i2s_pcm_monitor monitor(.bck(bck),.lrck(lrck),.din(din));
    integer previous_gain=65535,delta,k;
    always @(negedge clk) begin
        if($time>2000) begin
            if((^dut.fsr_gain)===1'bx) $fatal(1,"Unknown production FSR gain");
            delta=dut.fsr_gain-previous_gain;if(delta<0) delta=-delta;
            if(delta>64) $fatal(1,"Production FSR gain changed by more than one slew step");
            previous_gain=dut.fsr_gain;
        end
    end
    initial begin
        dut.u_fsr_adc.adc_inst.sim_value=1200;
        #500000;
        if(dut.fsr_gain!==65535) $fatal(1,"Production FSR initial full gain failed");
        #1100000;
        if(dut.fsr_adc_raw!==1200 || dut.fsr_adc_sample!==600 ||
           dut.fsr_gain>=65535 || dut.fsr_gain<63900)
            $fatal(1,"Production on-chip ADC/force-to-gain fall failed");
        dut.u_fsr_adc.adc_inst.sim_value=0;
        #1000000;
        if(dut.fsr_adc_sample!==0 || dut.fsr_gain>=65535 || dut.fsr_adc_timeout)
            $fatal(1,"Production on-chip ADC release failed");
        #1200000;
        if(dut.fsr_gain!==65535 || dut.u_fsr_adc.adc_inst.conversions!=3)
            $fatal(1,"Production gain did not return to full/three conversions");
        for(k=0;k<monitor.pcm_count;k=k+1)
            if(monitor.pcm[k]!=0) $fatal(1,"Production pressure alone produced I2S audio");
        $display("PASS [production FSR pipeline]: three on-chip ADC modeled conversions, force lowers gain, release restores full, bounded 64-LSB steps, idle I2S; %0d stereo pairs",monitor.pair_count);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #4500000;$fatal(1,"Production FSR pipeline timeout");end
endmodule
