`timescale 1ns/1ps
module tb_audio_units;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #10 clk = ~clk;
    reg sample_ce = 1'b0;
    wire signed [15:0] sine_sample;
    nco_sine #(.INC(32'h01000000)) nco (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce), .sample(sine_sample));

    reg key_s1 = 1'b0;
    reg signed [15:0] gain_input = 16'sd0;
    wire signed [15:0] half_sample, quarter_sample;
    volume_key half_gain (.clk(clk), .resetn(resetn), .key_s1(key_s1),
        .nco_sample(gain_input), .sample(half_sample));
    volume_key #(.VOLUME_SHIFT(2)) quarter_gain (
        .clk(clk), .resetn(resetn), .key_s1(key_s1),
        .nco_sample(gain_input), .sample(quarter_sample));

    reg bck_fall_ce = 1'b0;
    reg [5:0] bit_index = 6'd0;
    reg signed [15:0] tx_sample = 16'sd0;
    wire din;
    i2s_tx tx (.clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(tx_sample), .din(din));

    integer index;
    integer reference_value;
    real reference_sine;
    reg expected_bit;
    integer slot_bit;
    integer frame_tests = 0;

    task check_gain;
        input signed [15:0] value;
        begin
            @(negedge clk) gain_input = value;
            #1;
            if (half_sample !== (value >>> 1) || quarter_sample !== (value >>> 2))
                $fatal(1, "Signed gain failed for PCM=%0d", value);
        end
    endtask

    task send_frame;
        input [15:0] frame_word;
        integer position;
        begin
            for (position = 0; position < 64; position = position + 1) begin
                @(negedge clk);
                bit_index = position;
                bck_fall_ce = 1'b1;
                // Deliberately change the input after the left latch and at
                // the right boundary. Both channels must retain frame_word.
                tx_sample = (position == 0) ? frame_word : ~frame_word;
                slot_bit = position % 32;
                if (slot_bit >= 1 && slot_bit <= 16)
                    expected_bit = frame_word[16-slot_bit];
                else
                    expected_bit = 1'b0;
                @(posedge clk); #1;
                if (din !== expected_bit)
                    $fatal(1, "TX bit mismatch word=%h position=%0d", frame_word, position);
                @(negedge clk);
                bck_fall_ce = 1'b0;
                tx_sample = 16'h5aa5;
                @(posedge clk); #1;
                if (din !== expected_bit)
                    $fatal(1, "TX changed without falling-edge enable");
            end
            frame_tests = frame_tests + 1;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        resetn = 1'b1;
        @(posedge clk); #1;
        if (sine_sample !== 16'sd0 || half_sample !== 16'sd0 || din !== 1'b0)
            $fatal(1, "Initial state is not silent");
        // Exhaust all 256 sine addresses, including both signed quadrants.
        for (index = 0; index < 256; index = index + 1) begin
            reference_sine = 32767.0 * $sin(6.283185307179586 * index / 256.0);
            reference_value = (reference_sine >= 0.0)
                ? $rtoi(reference_sine + 0.5) : $rtoi(reference_sine - 0.5);
            if ($signed(sine_sample) !== reference_value)
                $fatal(1, "Sine LUT mismatch at address=%0d", index);
            @(negedge clk) sample_ce = 1'b1;
            @(posedge clk); #1;
            @(negedge clk) sample_ce = 1'b0;
            @(posedge clk); #1;
        end
        if (sine_sample !== 16'sd0)
            $fatal(1, "Phase accumulator did not wrap at 2^32");

        @(negedge clk);
        key_s1 = 1'b1;
        gain_input = -16'sd3;
        @(posedge clk); #1;
        if (half_sample !== 16'sd0)
            $fatal(1, "Key bypassed first synchronizer stage");
        @(posedge clk); #1;
        if (half_sample !== -16'sd2 || quarter_sample !== -16'sd1)
            $fatal(1, "Key / arithmetic shift failed after two stages");
        check_gain(16'sh8000);
        check_gain(16'sh7fff);
        check_gain(-16'sd1);
        check_gain(16'sd1);
        @(negedge clk) key_s1 = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (half_sample !== 16'sd0 || quarter_sample !== 16'sd0)
            $fatal(1, "Gain block did not mute after release");

        send_frame(16'h8000);
        send_frame(16'h7fff);
        send_frame(16'ha501);
        send_frame(16'h5a80);
        send_frame(16'h0001);
        send_frame(16'hffff);
        send_frame(16'h0000);
        $display("PASS [units]: all 256 sine values and phase wrap, two-stage key sync, signed half/quarter gain, %0d adversarial stereo TX frames", frame_tests);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "Unit-test timeout");
    end
endmodule
