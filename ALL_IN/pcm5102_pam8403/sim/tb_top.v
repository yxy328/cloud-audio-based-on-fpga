`timescale 1ns/1ps
// Decode only the exported I2S pins. Expected PCM comes from an independent
// mathematical sine / key synchronizer model, not the DUT shift register.
module tb_top;
    reg clk = 1'b0;
    reg key_s1 = 1'b0;
    wire i2s_bck, i2s_lrck, i2s_din;
    top dut (.clk(clk), .key_s1(key_s1), .i2s_bck(i2s_bck),
             .i2s_lrck(i2s_lrck), .i2s_din(i2s_din));
    always #10 clk = ~clk;

    integer master_edges = 0;
    reg ref_meta = 1'b0;
    reg ref_sync = 1'b0;
    reg key_at_latch = 1'b0;
    always @(posedge clk) begin
        master_edges = master_edges + 1;
        key_at_latch = ref_sync;
        if (master_edges <= 63) begin
            ref_meta <= 1'b0;
            ref_sync <= 1'b0;
        end else begin
            ref_meta <= key_s1;
            ref_sync <= ref_meta;
        end
    end

    reg [31:0] ref_phase = 32'd0;
    reg signed [15:0] expected_frame = 16'sd0;
    reg expected_key = 1'b0;
    integer sine_value;
    real scaled_sine;
    integer frame_count = 0;
    time last_frame_edge = 0;
    integer bck_edges = 0;
    integer last_frame_bck = 0;
    always @(negedge i2s_lrck) begin
        #1;
        if (last_frame_edge != 0) begin
            if (($time - 1 - last_frame_edge) != 20480)
                $fatal(1, "LRCK period is not 20480 ns");
            if ((bck_edges - last_frame_bck) != 64)
                $fatal(1, "LRCK period is not 64 BCK periods");
        end
        last_frame_edge = $time - 1;
        last_frame_bck = bck_edges;
        scaled_sine = 32767.0 * $sin(6.283185307179586 * ref_phase[31:24] / 256.0);
        if (scaled_sine >= 0.0)
            sine_value = $rtoi(scaled_sine + 0.5);
        else
            sine_value = $rtoi(scaled_sine - 0.5);
        expected_key = key_at_latch;
        expected_frame = expected_key ? (sine_value >>> 1) : 16'sd0;
        ref_phase = ref_phase + 32'd38_702_432;
        frame_count = frame_count + 1;
    end

    time last_bck_edge = 0;
    time last_bck_rise = 0;
    time last_bck_fall = 0;
    always @(i2s_bck) begin
        if ($time > 0 && dut.resetn) begin
            if (last_bck_edge != 0 && ($time - last_bck_edge) != 160)
                $fatal(1, "BCK half-period is not 160 ns");
            last_bck_edge = $time;
        end
    end
    always @(negedge i2s_bck) last_bck_fall = $time;
    always @(i2s_din) begin
        if ($time > 0 && dut.resetn) begin
            #1;
            if (i2s_bck !== 1'b0 || ($time - 1) != last_bck_fall)
                $fatal(1, "DIN changed away from a BCK falling edge");
        end
    end
    always @(i2s_lrck) begin
        if ($time > 0 && dut.resetn) begin
            #1;
            if (i2s_bck !== 1'b0 || ($time - 1) != last_bck_fall)
                $fatal(1, "LRCK changed away from a BCK falling edge");
        end
    end

    reg started = 1'b0;
    reg last_lrck = 1'b1;
    integer slot_bit = 0;
    reg [15:0] decoded_word = 16'd0;
    reg [15:0] left_word = 16'd0;
    integer channel_words = 0;
    integer stereo_pairs = 0;
    integer muted_words = 0;
    integer nonzero_words = 0;
    integer positive_words = 0;
    integer negative_words = 0;
    always @(posedge i2s_bck) begin
        if (last_bck_rise != 0 && ($time - last_bck_rise) != 320)
            $fatal(1, "BCK period is not 320 ns");
        last_bck_rise = $time;
        bck_edges = bck_edges + 1;
        #1;
        if ((^{i2s_bck, i2s_lrck, i2s_din}) === 1'bx)
            $fatal(1, "Unknown state on I2S pins");
        if (!started && i2s_lrck == 1'b0) begin
            started = 1'b1;
            last_lrck = i2s_lrck;
            slot_bit = 0;
        end else if (started) begin
            if (i2s_lrck != last_lrck) begin
                if (slot_bit != 31)
                    $fatal(1, "Channel slot is not 32 BCK periods");
                slot_bit = 0;
                last_lrck = i2s_lrck;
            end else begin
                slot_bit = slot_bit + 1;
                if (slot_bit > 31)
                    $fatal(1, "LRCK did not change after 32 BCK periods");
            end
        end
        if (started) begin
            if (slot_bit == 0 || slot_bit >= 17) begin
                if (i2s_din !== 1'b0)
                    $fatal(1, "I2S delay / padding bit is not zero");
            end else begin
                // Bit 1 (after the LRCK edge's delay cycle) must be MSB.
                if (i2s_din !== expected_frame[16-slot_bit])
                    $fatal(1, "I2S bit mismatch: frame=%0d LRCK=%b bit=%0d", frame_count, i2s_lrck, slot_bit);
                decoded_word = {decoded_word[14:0], i2s_din};
                if (slot_bit == 16) begin
                    if (decoded_word !== expected_frame)
                        $fatal(1, "Decoded PCM differs from mathematical reference");
                    if ($signed(decoded_word) > 16383 || $signed(decoded_word) < -16384)
                        $fatal(1, "PCM exceeds half-volume bounds");
                    channel_words = channel_words + 1;
                    if (!expected_key) begin
                        if (decoded_word !== 16'd0)
                            $fatal(1, "Key release did not produce digital silence");
                        muted_words = muted_words + 1;
                    end else if (decoded_word != 16'd0) begin
                        nonzero_words = nonzero_words + 1;
                        if ($signed(decoded_word) > 0)
                            positive_words = positive_words + 1;
                        else
                            negative_words = negative_words + 1;
                    end
                    if (!i2s_lrck)
                        left_word = decoded_word;
                    else begin
                        if (decoded_word !== left_word)
                            $fatal(1, "Left and right samples differ within a frame");
                        stereo_pairs = stereo_pairs + 1;
                    end
                end
            end
        end
    end

    initial begin
        $dumpfile("sim/build/tb_top.vcd");
        $dumpvars(0, tb_top);
        // Asynchronous transitions include a release within a stereo frame.
        #200000 key_s1 = 1'b1;
        #1300777 key_s1 = 1'b0;
        #349223 key_s1 = 1'b1;
        #350000 key_s1 = 1'b0;
        #800000;
        if (frame_count < 145 || stereo_pairs < 140 || channel_words < 280)
            $fatal(1, "Too few complete I2S frames decoded");
        if (muted_words < 50 || nonzero_words < 100 || positive_words == 0 || negative_words == 0)
            $fatal(1, "Missing silence / active / positive / negative sample coverage");
        $display("PASS [top 3ms]: BCK=3.125MHz LRCK=48.828125kHz ratio=64, I2S one-bit delay/MSB/padding, %0d stereo pairs, %0d muted words, %0d nonzero words", stereo_pairs, muted_words, nonzero_words);
        $finish;
    end
endmodule
