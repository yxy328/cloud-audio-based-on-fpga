`timescale 1ns/1ps
// A tap on the exact sample latched by i2s_tx, never an audio processing stage.
// 48 columns cover all 512 samples (11,11,10 samples repeated 16 times).
// Signed PCM extrema are retained before range selection, so a large signal
// can expand the displayed range without reinterpreting a clipped bitmap.
// Double buffering swaps only at a complete panel RGB5/PWM frame boundary.
module audio_visualizer (
    input wire clk, resetn, sample_ce, display_boundary, service_ce,style_ce,
    input wire [1:0] visual_mode,
    input wire [1:0] reference_ratio,reference_phase,
    input wire [15:0] scope_fsr_gain,
    input wire signed [15:0] mixed_sample, touch0, touch1, sensor_sample, guitar_sample,
    input wire [5:0] pixel_x,
    input wire [4:0] pixel_row,
    output reg [14:0] upper_rgb, lower_rgb,
    output wire [103:0] telemetry
);
    // One BSRAM: wave banks 0..127, 64x32 XY bitmap banks 128..383.
    // Display reads are prefetched. XY read/modify/write uses row blanking,
    // leaving the existing 133-clock HUB row period and RGB setup unchanged.
    (* syn_ramstyle="block_ram" *) reg [19:0] picture [0:511];
    reg capture_bank, display_bank, capture_ready, display_valid;
    reg clearing,capture_full,wave_pending,xy_pending,rmw_busy;
    reg [6:0] clear_index;
    reg [8:0] wave_address,xy_address,rmw_address;
    reg [19:0] wave_value;
    reg [3:0] xy_bit,rmw_bit;
    reg [5:0] capture_column;
    reg [3:0] sample_phase;
    reg [1:0] group_phase;
    // At maximum x32 gain a pixel is 64 PCM counts: ten signed bits retain
    // every visible step. Both endpoints share the existing RAM with XY.
    reg signed [9:0] minimum_sample,maximum_sample,previous_sample;
    wire signed [9:0] quantized_sample=mixed_sample[15:6];
    wire signed [9:0] next_minimum=quantized_sample<minimum_sample ? quantized_sample : minimum_sample;
    wire signed [9:0] next_maximum=quantized_sample>maximum_sample ? quantized_sample : maximum_sample;
    wire column_done=sample_phase==(group_phase==2 ? 4'd9 : 4'd10);
    // ceil(abs(PCM)/256), including -32768. Eight-bit peak storage keeps
    // conservative range protection without a full-width absolute/max chain.
    wire [7:0] sample_magnitude=mixed_sample[15] ? (~mixed_sample[15:8]+8'd1) :
        {1'b0,mixed_sample[14:8]}+(|mixed_sample[7:0]);
    reg [7:0] capture_peak;
    // A separate PCM/64 axis drives color only. Compensate the negative
    // arithmetic truncation so both signs use floor(abs(PCM)/64), including
    // +/-1 -> 0. The 10-bit -512 magnitude is 512 and saturates normally.
    wire [9:0] magnitude64_full=quantized_sample[9] ?
        (~quantized_sample+{9'd0,(mixed_sample[5:0]==6'd0)}) : quantized_sample;
    wire [5:0] magnitude64=magnitude64_full>10'd63 ? 6'd63 : magnitude64_full[5:0];
    reg [5:0] capture_peak64;
    reg [1:0] capture_range;
    reg [2:0] shown_range;
    // Normal instrument output is attenuated before this tap. Start at x8,
    // then let FSR suggest x16/x32. True peaks always override with a wider
    // x1..x32 range; both endpoints retain enough precision for every range.
    wire [2:0] safe_range=capture_peak>64 ? 3'd0 : capture_peak>32 ? 3'd1 :
        capture_peak>16 ? 3'd2 : capture_range==0 || capture_peak>8 ? 3'd3 :
        capture_range==1 || capture_peak>4 ? 3'd4 : 3'd5;
    reg [4:0] sample_y;
    reg [5:0] sample_x;
    reg [1:0] capture_ratio,capture_phase,shown_ratio,shown_phase;
    wire capture_restart=capture_ready && display_boundary;
    wire [5:0] reference_x;
    wire [4:0] reference_y;
    lissajous_reference u_reference (
        .clk(clk),.resetn(resetn),.restart(capture_restart),
        .sample_ce(sample_ce && !capture_full && !clearing),
        .ratio(capture_ratio),.phase(capture_phase),.x(reference_x),.y(reference_y));
    wire [5:0] xy_x=capture_ratio==0 ? sample_x : reference_x;
    wire signed [15:0] scaled_y=16'sd16-(mixed_sample>>>9);
    wire signed [15:0] scaled_x=16'sd32+(mixed_sample>>>8);
    always @* begin
        if (mixed_sample > 16'sd7680) sample_y = 1;
        else if (mixed_sample < -16'sd7680) sample_y = 31;
        else sample_y = scaled_y[4:0];
        if(mixed_sample>16'sd7680) sample_x=62;
        else if(mixed_sample < -16'sd7680) sample_x=2;
        else sample_x=scaled_x[5:0];
    end
    // The pointer is stable for 1024 clocks between samples. A synchronous
    // read therefore supplies the same delayed point at sample_ce, while
    // moving the 32-entry history and its large mux into one block RAM.
    (* syn_ramstyle="block_ram" *) reg [4:0] history[0:31];
    reg [4:0] history_q;
    reg [4:0] history_pointer;
    reg [5:0] history_count;
    wire [4:0] xy_y=capture_ratio==0 ? history_q : reference_y;
    always @(posedge clk)history_q<=history[history_pointer];
    always @(posedge clk) begin
        if(!resetn) begin history_pointer<=0;history_count<=0;end
        else if(sample_ce) begin
            history[history_pointer]<=sample_y;
            history_pointer<=history_pointer+1'b1;
            if(history_count<32) history_count<=history_count+1'b1;
        end
    end
    wire start_xy=service_ce && !clearing && xy_pending && !rmw_busy;
    wire write_wave=service_ce && !clearing && !xy_pending && wave_pending && !rmw_busy;
    wire [8:0] clear_address=9'd128+{capture_bank,7'd0}+{2'd0,clear_index};
    wire [8:0] display_address=visual_mode==2 ?
        9'd128+{display_bank,7'd0}+{2'd0,pixel_row,2'd0}+{7'd0,pixel_x[5:4]} :
        {2'd0,display_bank,(pixel_x-6'd16)};
    wire [8:0] read_address=start_xy ? xy_address : display_address;
    reg [19:0] display_data;
    wire [19:0] display_range=display_data;
    always @(posedge clk) begin
        display_data<=picture[read_address];
        if(resetn) begin
            if(rmw_busy) picture[rmw_address]<=display_data | (20'd1<<rmw_bit);
            else if(clearing && service_ce) picture[clear_address]<=0;
            else if(write_wave) picture[wave_address]<=wave_value;
        end
    end
    always @(posedge clk) begin
        if (!resetn) begin
            capture_bank <= 1; display_bank <= 0;
            capture_ready <= 0; display_valid <= 0;
            clearing<=1;clear_index<=0;capture_full<=0;
            wave_pending<=0;xy_pending<=0;rmw_busy<=0;
            wave_address<=0;xy_address<=0;rmw_address<=0;wave_value<=0;xy_bit<=0;rmw_bit<=0;
            capture_column <= 0; sample_phase <= 0;
            minimum_sample<=0;maximum_sample<=0;previous_sample<=0;group_phase<=0;
            capture_peak<=0;capture_range<=0;shown_range<=0;
            capture_peak64<=0;
            capture_ratio<=0;capture_phase<=0;shown_ratio<=0;shown_phase<=0;
        end else begin
            rmw_busy<=0;
            if(clearing && service_ce) begin
                clear_index<=clear_index+1'b1;
                if(clear_index==127) clearing<=0;
            end
            if(start_xy) begin
                rmw_busy<=1;rmw_address<=xy_address;rmw_bit<=xy_bit;xy_pending<=0;
            end
            if(write_wave) wave_pending<=0;
            if(capture_full && !wave_pending && !xy_pending && !rmw_busy) capture_ready<=1;
            if (capture_ready && display_boundary) begin
                shown_range<=safe_range;
                capture_peak<=0;
                capture_peak64<=0;
                // Quantize actual applied FSR gain; 1.56% hysteresis on
                // returning to a wider range prevents boundary chatter.
                case(capture_range)
                    0:if(scope_fsr_gain<=32768)capture_range<=scope_fsr_gain<=16384 ? 2'd2 : 2'd1;
                    1:if(scope_fsr_gain>33792)capture_range<=0;
                      else if(scope_fsr_gain<=16384)capture_range<=2;
                    2:if(scope_fsr_gain>33792)capture_range<=0;
                      else if(scope_fsr_gain>17408)capture_range<=1;
                    default:capture_range<=0;
                endcase
                shown_ratio<=capture_ratio;shown_phase<=capture_phase;
                capture_ratio<=reference_ratio;capture_phase<=reference_phase;
                display_bank <= capture_bank;
                capture_bank <= display_bank;
                display_valid <= 1;
                capture_ready <= 0;
                capture_full<=0;clearing<=1;clear_index<=0;
            end
            if (sample_ce && !capture_full && !clearing) begin
                if(sample_magnitude>capture_peak)capture_peak<=sample_magnitude;
                if(magnitude64>capture_peak64)capture_peak64<=magnitude64;
                if(history_count==32) begin
                    xy_address<=9'd128+{capture_bank,7'd0}+{2'd0,xy_y,2'd0}+{7'd0,xy_x[5:4]};
                    xy_bit<=xy_x[3:0];xy_pending<=1;
                end
                sample_phase <= column_done ? 4'd0 : sample_phase+1'b1;
                if (sample_phase == 0) begin
                    minimum_sample<=capture_column!=0 && previous_sample<quantized_sample ? previous_sample : quantized_sample;
                    maximum_sample<=capture_column!=0 && previous_sample>quantized_sample ? previous_sample : quantized_sample;
                end else begin
                    minimum_sample<=next_minimum;
                    maximum_sample<=next_maximum;
                    if (column_done) begin
                        wave_address<={2'd0,capture_bank,capture_column};
                        wave_value<={next_maximum,next_minimum};wave_pending<=1;
                        previous_sample<=quantized_sample;
                        capture_column<=capture_column==47 ? 6'd0 : capture_column+1'b1;
                        group_phase<=group_phase==2 ? 2'd0 : group_phase+1'b1;
                        if (capture_column == 47) capture_full <= 1;
                    end
                end
            end
        end
    end

    wire [14:0] scope_upper,scope_lower;
    wire xy_label_on;
    audio_scope u_scope(.clk(clk),.resetn(resetn),.service_ce(style_ce),
        .publish(capture_restart),.capture_peak(capture_peak),.capture_peak64(capture_peak64),
        .shown_range(shown_range),.display_valid(display_valid),.range_word(display_range),
        .visual_mode(visual_mode),.shown_ratio(shown_ratio),.shown_phase(shown_phase),.xy_label_on(xy_label_on),
        .pixel_x(pixel_x),.pixel_row(pixel_row),.upper_rgb(scope_upper),.lower_rgb(scope_lower));

    wire [79:0] spectrum_levels;
    wire spectrum_valid,spectrum_done;
    reg [79:0] shown_spectrum;
    reg shown_spectrum_valid;
    audio_spectrum u_spectrum (
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.sample(mixed_sample),
        .levels(spectrum_levels),.valid(spectrum_valid),.done(spectrum_done),.peak_bin(),.peak_magnitude()
    );
    always @(posedge clk) begin
        if(!resetn) begin shown_spectrum<=0;shown_spectrum_valid<=0;end
        else if(display_boundary) begin shown_spectrum<=spectrum_levels;shown_spectrum_valid<=spectrum_valid;end
    end

    // Fixed display gain only. Magnitude handles -32768 and the 17-bit
    // sum of the two touch groups without signed wraparound or multipliers.
    function [5:0] amplitude;
        input signed [16:0] value;
        reg [16:0] magnitude;
        begin
            magnitude = value[16] ? (~value+17'd1) : value;
            amplitude = magnitude >= 17'd7168 ? 6'd56 : magnitude[12:7];
        end
    endfunction
    wire signed [16:0] touch_sum = {touch0[15],touch0}+{touch1[15],touch1};
    wire [5:0] touch_level = amplitude(touch_sum);
    wire [5:0] sensor_level = amplitude({sensor_sample[15],sensor_sample});
    wire [5:0] guitar_level = amplitude({guitar_sample[15],guitar_sample});
    reg [5:0] touch_peak, sensor_peak, guitar_peak;
    reg [5:0] shown_touch, shown_sensor, shown_guitar;
    // Read-only taps on the same frame-latched values rendered on the panel.
    assign telemetry={display_valid,shown_spectrum_valid,shown_ratio,shown_phase,
        shown_touch,shown_sensor,shown_guitar,shown_spectrum};
    reg [8:0] decay_count;
    always @(posedge clk) begin
        if (!resetn) begin
            touch_peak <= 0; sensor_peak <= 0; guitar_peak <= 0;
            shown_touch <= 0; shown_sensor <= 0; shown_guitar <= 0;
            decay_count <= 0;
        end else begin
            if (sample_ce) begin
                decay_count <= decay_count+1'b1;
                if (touch_level >= touch_peak) touch_peak <= touch_level;
                else if (&decay_count && touch_peak != 0) touch_peak <= touch_peak-1'b1;
                if (sensor_level >= sensor_peak) sensor_peak <= sensor_level;
                else if (&decay_count && sensor_peak != 0) sensor_peak <= sensor_peak-1'b1;
                if (guitar_level >= guitar_peak) guitar_peak <= guitar_level;
                else if (&decay_count && guitar_peak != 0) guitar_peak <= guitar_peak-1'b1;
            end
            if (display_boundary) begin
                shown_touch <= touch_peak;
                shown_sensor <= sensor_peak;
                shown_guitar <= guitar_peak;
            end
        end
    end

    reg [5:0] bar_level;
    reg [14:0] bar_color;
    reg bar_row;
    wire [5:0] bar_x = pixel_x-6'd6;
    wire [4:0] spectrum_height=shown_spectrum[pixel_x[5:2]*5 +: 5];
    always @* begin
        upper_rgb = 0;
        // Quiet baseline and four time-grid columns remain visible in silence.
        if (pixel_row == 16 || pixel_x[3:0] == 0) upper_rgb = {5'd0,5'd1,5'd3};
        if(visual_mode==2) begin
            upper_rgb=0;
            if(pixel_x==32 || pixel_row==16) upper_rgb={5'd1,5'd1,5'd3};
            if(display_valid && display_data[pixel_x[3:0]]) upper_rgb={5'd24,5'd4,5'd31};
        end else if(visual_mode==3) begin
            upper_rgb=pixel_row==31 ? {5'd2,5'd2,5'd3} : 15'd0;
            if(shown_spectrum_valid && pixel_x[1:0]!=3 && spectrum_height!=0 && pixel_row>31-spectrum_height) begin
                if(pixel_x<24) upper_rgb={5'd0,5'd28,5'd6};
                else if(pixel_x<44) upper_rgb={5'd0,5'd24,5'd31};
                else upper_rgb={5'd31,5'd14,5'd0};
            end
        end

        bar_level = 0; bar_color = 0; bar_row = 0;
        if (pixel_row >= 6 && pixel_row <= 10) begin
            bar_row = 1; bar_level = shown_touch; bar_color = {5'd0,5'd28,5'd3};
        end else if (pixel_row >= 14 && pixel_row <= 18) begin
            bar_row = 1; bar_level = shown_sensor; bar_color = {5'd0,5'd25,5'd31};
        end else if (pixel_row >= 22 && pixel_row <= 26) begin
            bar_row = 1; bar_level = shown_guitar; bar_color = {5'd31,5'd12,5'd0};
        end
        lower_rgb = 0;
        if (bar_row) begin
            if (pixel_x >= 1 && pixel_x <= 3) lower_rgb = bar_color;
            if (pixel_x >= 6 && pixel_x < 62) begin
                lower_rgb = {5'd1,5'd1,5'd2};
                if (bar_x < bar_level) lower_rgb = bar_color;
            end
        end
        if(xy_label_on)
            lower_rgb={5'd18,5'd18,5'd18};
        if(visual_mode==1)begin upper_rgb=scope_upper;lower_rgb=scope_lower;end
    end
endmodule
