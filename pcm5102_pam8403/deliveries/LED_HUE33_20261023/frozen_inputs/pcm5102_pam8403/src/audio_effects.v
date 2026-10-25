`timescale 1ns/1ps
// One sample per completed synthesis frame, always finishes in five clocks.
// Long echoes filter and decimate only wet samples; the dry path retains every frame.
// W0..8 sets wet contribution 0..1/2. RAM is never reset in a logic loop;
// fill count masks uninitialized contents and clears tails on a mode change.
module audio_effects #(
    parameter integer ADDRESS_BITS=13
)(
    input wire clk,resetn,sample_valid,
    input wire signed [15:0] dry,
    input wire [1:0] mode,
    input wire [3:0] wet,
    input wire [1:0] echo_tap,
    output reg signed [15:0] sample,
    output reg valid
);
    localparam integer LENGTH=1<<ADDRESS_BITS;
    (* syn_ramstyle="block_ram" *) reg signed [15:0] memory [0:LENGTH-1];
    reg [ADDRESS_BITS-1:0] pointer,read_address;
    reg [ADDRESS_BITS:0] filled;
    reg [15:0] lfo;
    wire [7:0] triangle=lfo[15] ? ~lfo[14:7] : lfo[14:7];
    wire [ADDRESS_BITS-1:0] chorus_delay=1024+triangle;
    reg [1:0] previous_mode,held_mode;
    reg [3:0] held_wet;
    reg [2:0] state;
    reg signed [15:0] held_dry,tap;
    reg tap_valid;
    reg [1:0] previous_tap,held_tap;
    reg [2:0] capture_count;
    reg held_capture;
    reg signed [15:0] filtered;
    wire slow_echo=mode==1 && echo_tap!=0;
    wire [2:0] capture_last=echo_tap==1 ? 3'd1 : echo_tap==2 ? 3'd3 : 3'd5;
    wire configuration_changed=mode!=previous_mode || (mode==1 && echo_tap!=previous_tap);
    wire signed [16:0] filter_difference=$signed({dry[15],dry})-$signed({filtered[15],filtered});
    wire signed [16:0] filter_step=echo_tap==1 ? (filter_difference>>>1) : (filter_difference>>>2);
    wire signed [16:0] filter_next=$signed({filtered[15],filtered})+filter_step;
    reg signed [20:0] wet_product;
    // Q4 wet gain: [20:4] is the signed shifted result; extend to the
    // 18-bit accumulator before adding dry PCM and saturating.
    wire signed [17:0] wet_sample=$signed(wet_product[20:4]);
    reg signed [17:0] mix,feedback;
    function [15:0] saturate(input signed [17:0] x);
        begin
            if(x>32767) saturate=16'h7fff;
            else if(x< -32768) saturate=16'h8000;
            else saturate=x[15:0];
        end
    endfunction
    always @(posedge clk) begin
        if(!resetn) begin
            pointer<=0;filled<=0;lfo<=0;previous_mode<=0;held_mode<=0;held_wet<=0;
            previous_tap<=0;held_tap<=0;capture_count<=0;held_capture<=0;filtered<=0;
            state<=0;held_dry<=0;tap<=0;tap_valid<=0;read_address<=0;
            wet_product<=0;mix<=0;feedback<=0;sample<=0;valid<=0;
        end else begin
            valid<=0;
            case(state)
                0:if(sample_valid) begin
                    held_dry<=dry;held_mode<=mode;held_wet<=(wet>8) ? 4'd8 : wet;
                    previous_mode<=mode;previous_tap<=echo_tap;held_tap<=echo_tap;lfo<=lfo+1'b1;
                    if(!slow_echo)begin held_capture<=1;capture_count<=0;filtered<=0;end
                    else if(configuration_changed)begin
                        held_capture<=0;capture_count<=1;filtered<=echo_tap==1 ? (dry>>>1) : (dry>>>2);
                    end else if(capture_count==capture_last)begin
                        held_capture<=1;capture_count<=0;filtered<=filter_next[15:0];
                    end else begin held_capture<=0;capture_count<=capture_count+1'b1;filtered<=filter_next[15:0];end
                    if(configuration_changed) begin pointer<=0;filled<=0;tap_valid<=0;read_address<=0;end
                    else if(!slow_echo || capture_count==capture_last)begin
                        read_address<=(mode==2) ? pointer-chorus_delay : pointer;
                        tap_valid<=(mode==2) ? filled>=chorus_delay : filled==LENGTH;
                    end
                    state<=1;
                end
                1:begin if(held_capture)tap<=memory[read_address];state<=2;end
                2:begin
                    wet_product<=(tap_valid ? tap : 16'sd0)*$signed({1'b0,held_wet});
                    feedback<=((held_mode==1 && held_tap!=0) ? ($signed(filtered)>>>1) : ($signed(held_dry)>>>1))+
                        ((tap_valid && held_mode==1) ? ($signed(tap)>>>1) : 18'sd0);
                    state<=3;
                end
                3:begin
                    mix<=$signed(held_dry)+wet_sample;
                    if(held_capture)begin
                        memory[pointer]<=(held_mode==1) ? saturate(feedback) : held_dry;
                        pointer<=pointer+1'b1;
                        if(filled<LENGTH) filled<=filled+1'b1;
                    end
                    state<=4;
                end
                4:begin sample<=(held_mode==0) ? held_dry : saturate(mix);valid<=1;state<=0;end
                default:state<=0;
            endcase
        end
    end
endmodule
