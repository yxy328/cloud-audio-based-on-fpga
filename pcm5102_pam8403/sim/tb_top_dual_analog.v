`timescale 1ns/1ps
// Integration check: pressure (on-chip ADC) and slider (ADS1115) work at the
// same time and stay independent. Pressure drives touch volume/pitch while the
// slider drives master volume; neither channel disables the other.
// ANALOG/PRESSURE command decoding is covered by tb_hc05_extensions, so the
// mode registers are forced here to keep the simulation short.
module tb_top_dual_analog;
    reg clk = 0;
    always #10 clk = ~clk;
    reg [7:0] pads = 0;
    // Slider converter bus (J3 pins 31/32). The gesture bus is left unconnected.
    tri1 ads_scl, ads_sda;
    wire bck, lrck, din;

    reg [15:0] slider_code = 16'd0;

    top #(.KEY_CONFIRM_CYCLES(1000), .TOUCH_STARTUP_US(3000),
          .TOUCH_DEBOUNCE_MS(2), .TOUCH_MODE_DEBOUNCE_MS(2),
          .TOUCH_ADSR_RELEASE_SAMPLES(32), .ADSR_ATTACK_SAMPLES(4),
          .ADSR_DECAY_SAMPLES(4), .ADSR_RELEASE_SAMPLES(32),
          .SLIDER_STARTUP_MS(1), .SLIDER_POLL_MS(1),
          .FSR_SLEW_STEP(16'd8192), .FSR_PITCH_SLEW_STEP(16'd8192)) dut (
        .clk(clk), .key_s1(1'b0), .key_s2(1'b0), .ir_beam(8'hff),
        .touch_out(pads), .hc05_rx(1'b1), .hc05_tx(),
        .i2s_bck(bck), .i2s_lrck(lrck), .i2s_din(din), .touch_scl(),
        .slider_scl(ads_scl), .slider_sda(ads_sda));

    ads1115_model u_slider (
        .clk(clk), .scl(ads_scl), .sda(ads_sda), .present(1'b1), .code(slider_code));

    task settle;
        begin
            repeat (250000) @(negedge clk);
        end
    endtask

    initial begin
        // Pressure channel: heavy force must reach the minimum gain.
        force dut.u_fsr_adc.adc_inst.sim_value = {3'd0, 10'd1023, 1'b0};
        repeat (700000) @(negedge clk);
        if (!dut.resetn) $fatal(1, "Top did not leave reset");
        if (dut.fsr_gain !== 16'd16384)
            $fatal(1, "Pressure gain %0d did not follow heavy force", dut.fsr_gain);

        // Slider volume at zero must mute the master, pressure stays active.
        force dut.analog_mode = 3'd1;
        slider_code = 16'h0000;
        settle;
        if (dut.analog_available !== 1'b1) $fatal(1, "Slider channel not available");
        if (dut.master_target !== 13'd0) $fatal(1, "Slider zero did not mute master");
        if (dut.fsr_gain !== 16'd16384)
            $fatal(1, "Slider mode disabled the pressure channel");

        // Slider at full scale restores the manual ceiling.
        slider_code = 16'h7FFF;
        settle;
        if (dut.master_target !== 13'd4096) $fatal(1, "Slider full scale not unity");

        // Pressure pitch mode with the slider volume still active: both channels
        // must be in effect at the same time.
        force dut.fsr_pitch_mode = 1'b1;
        repeat (400000) @(negedge clk);
        if (dut.fsr_gain !== 16'hffff)
            $fatal(1, "Pitch mode did not restore unity volume");
        if (dut.fsr_pitch_ratio === 16'hffff)
            $fatal(1, "Pressure pitch did not bend with heavy force");
        if (dut.master_target !== 13'd4096)
            $fatal(1, "Slider volume lost while pressure pitch is active");

        // Slider falls back when the converter stops answering, pressure does not.
        slider_code = 16'h0000;
        settle;
        if (dut.master_target !== 13'd0) $fatal(1, "Slider zero did not mute master");
        force dut.u_slider_adc.timeout = 1'b1;
        repeat (10) @(negedge clk);
        if (dut.u_analog_expression.pitch_ratio !== dut.fsr_pitch_ratio)
            $fatal(1, "Slider fault did not fall back to pressure pitch");
        release dut.u_slider_adc.timeout;
        release dut.fsr_pitch_mode;
        release dut.analog_mode;

        $display("PASS [dual analog]: pressure gain/pitch and slider master volume are independent, both active together, slider fault falls back without muting pressure");
        $finish;
    end

    initial begin
        #80000000;
        $fatal(1, "Dual analog test timeout");
    end
endmodule
