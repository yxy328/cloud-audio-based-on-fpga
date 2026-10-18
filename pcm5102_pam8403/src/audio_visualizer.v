`timescale 1ns/1ps
// A tap on the exact sample latched by i2s_tx, never an audio processing stage.
// 64 columns x 8 samples = 10.486ms at 50MHz/1024. Each column stores its
// minimum/maximum screen y, preserving both polarities and brief transients.
// Double buffering swaps only at a complete panel RGB5/PWM frame boundary.
module audio_visualizer (
    input wire clk, resetn, sample_ce, display_boundary, service_ce,
    input wire [1:0] visual_mode,
    input wire [1:0] reference_ratio,reference_phase,
    input wire signed [15:0] mixed_sample, touch0, touch1, sensor_sample, guitar_sample,
    input wire [5:0] pixel_x,
    input wire [4:0] pixel_row,
    output reg [14:0] upper_rgb, lower_rgb
);
    // One BSRAM: wave banks 0..127, 64x32 XY bitmap banks 128..383.
    // Display reads are prefetched. XY read/modify/write uses row blanking,
    // leaving the existing 133-clock HUB row period and RGB setup unchanged.
    (* syn_ramstyle="block_ram" *) reg [15:0] picture [0:511];
    reg capture_bank, display_bank, capture_ready, display_valid;
    reg clearing,capture_full,wave_pending,xy_pending,rmw_busy;
    reg [6:0] clear_index;
    reg [8:0] wave_address,xy_address,rmw_address;
    reg [9:0] wave_value;
    reg [3:0] xy_bit,rmw_bit;
    reg [5:0] capture_column;
    reg [2:0] sample_phase;
    reg [4:0] minimum_y, maximum_y;
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
    wire [4:0] next_minimum = sample_y < minimum_y ? sample_y : minimum_y;
    wire [4:0] next_maximum = sample_y > maximum_y ? sample_y : maximum_y;
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
        {2'd0,display_bank,pixel_x};
    wire [8:0] read_address=start_xy ? xy_address : display_address;
    reg [15:0] display_data;
    wire [9:0] display_range=display_data[9:0];
    always @(posedge clk) begin
        display_data<=picture[read_address];
        if(resetn) begin
            if(rmw_busy) picture[rmw_address]<=display_data | (16'd1<<rmw_bit);
            else if(clearing && service_ce) picture[clear_address]<=0;
            else if(write_wave) picture[wave_address]<={6'd0,wave_value};
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
            minimum_y <= 16; maximum_y <= 16;
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
                shown_ratio<=capture_ratio;shown_phase<=capture_phase;
                capture_ratio<=reference_ratio;capture_phase<=reference_phase;
                display_bank <= capture_bank;
                capture_bank <= display_bank;
                display_valid <= 1;
                capture_ready <= 0;
                capture_full<=0;clearing<=1;clear_index<=0;
            end
            if (sample_ce && !capture_full && !clearing) begin
                if(history_count==32) begin
                    xy_address<=9'd128+{capture_bank,7'd0}+{2'd0,xy_y,2'd0}+{7'd0,xy_x[5:4]};
                    xy_bit<=xy_x[3:0];xy_pending<=1;
                end
                sample_phase <= sample_phase+1'b1;
                if (sample_phase == 0) begin
                    minimum_y <= sample_y;
                    maximum_y <= sample_y;
                end else begin
                    minimum_y <= next_minimum;
                    maximum_y <= next_maximum;
                    if (sample_phase == 7) begin
                        wave_address<={2'd0,capture_bank,capture_column};
                        wave_value<={next_minimum,next_maximum};wave_pending<=1;
                        capture_column <= capture_column+1'b1;
                        if (capture_column == 63) capture_full <= 1;
                    end
                end
            end
        end
    end

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
    // 3x5 source/parameter label in otherwise unused rows 32..36.
    // REF is a mathematical reference; AUD is the actual delayed audio mix.
    reg [7:0] label_char;
    wire [11:0] phase_digits=shown_phase==0 ? 12'h000 :
        shown_phase==1 ? 12'h045 : shown_phase==2 ? 12'h090 : 12'h135;
    always @* begin
        label_char=" ";
        case(pixel_x[5:2])
            1:label_char=shown_ratio==0 ? "A" : "R";
            2:label_char=shown_ratio==0 ? "U" : "E";
            3:label_char=shown_ratio==0 ? "D" : "F";
            5:if(shown_ratio!=0) label_char=shown_ratio==3 ? "2" : "1";
            6:if(shown_ratio!=0) label_char=":";
            7:if(shown_ratio!=0) label_char=shown_ratio==2 ? "2" : shown_ratio==3 ? "3" : "1";
            9:if(shown_ratio!=0) label_char="P";
            10:if(shown_ratio!=0) label_char="0"+phase_digits[11:8];
            11:if(shown_ratio!=0) label_char="0"+phase_digits[7:4];
            12:if(shown_ratio!=0) label_char="0"+phase_digits[3:0];
            default:label_char=" ";
        endcase
    end
    function [14:0] glyph;
        input [7:0] ch;
        begin case(ch)
            "0":glyph=15'b111_101_101_101_111;
            "1":glyph=15'b010_110_010_010_111;
            "2":glyph=15'b110_001_010_100_111;
            "3":glyph=15'b110_001_010_001_110;
            "4":glyph=15'b101_101_111_001_001;
            "5":glyph=15'b111_100_110_001_110;
            "9":glyph=15'b111_101_111_001_110;
            ":":glyph=15'b000_010_000_010_000;
            "A":glyph=15'b010_101_111_101_101;
            "U":glyph=15'b101_101_101_101_111;
            "D":glyph=15'b110_101_101_101_110;
            "R":glyph=15'b110_101_110_101_101;
            "E":glyph=15'b111_100_110_100_111;
            "F":glyph=15'b111_100_110_100_100;
            "P":glyph=15'b110_101_110_100_100;
            default:glyph=0;
        endcase end
    endfunction
    wire [14:0] label_glyph=glyph(label_char);
    wire [4:0] glyph_index=5'd14-({pixel_row[2:0],1'b0}+pixel_row[2:0])-pixel_x[1:0];
    always @* begin
        upper_rgb = 0;
        // Quiet baseline and four time-grid columns remain visible in silence.
        if (pixel_row == 16 || pixel_x[3:0] == 0) upper_rgb = {5'd0,5'd1,5'd3};
        if (display_valid && pixel_row >= display_range[9:5] && pixel_row <= display_range[4:0])
            upper_rgb = {5'd0,5'd26,5'd31};
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
        if(visual_mode==2 && display_valid && pixel_row<5 && pixel_x[1:0]!=3 && label_glyph[glyph_index])
            lower_rgb={5'd18,5'd18,5'd18};
    end
endmodule
