`timescale 1ns/1ps
// Two independent analog channels:
//   pressure (on-chip ADC) -> touch volume or pitch, always available;
//   slider   (ADS1115 AIN1) -> master volume, touch pitch, vibrato depth or
//           effect wet amount, selected by the App.
// MODE selects only what the slider does. MODE=0 means "slider idle" while the
// pressure channel keeps working. Pressure pitch is the base ratio for every
// slider mode; slider pitch overrides it when MODE=2 is active.
module analog_expression(
    input wire clk,resetn,frame_ce,
    input wire [2:0] mode,
    input wire [9:0] adc_sample,
    input wire [9:0] adc_min,adc_max,
    input wire adc_valid,adc_timeout,
    input wire [15:0] pressure_pitch,
    input wire [4:0] volume,
    input wire [3:0] wet,
    output wire [15:0] pitch_ratio,
    output wire [12:0] master_gain,
    output wire [3:0] effect_wet,
    output wire [9:0] position,
    output wire available
);
    reg [9:0] code;
    reg [12:0] age,lfo;
    reg seen;
    reg converting;
    reg [4:0] divide_left;
    reg [19:0] quotient;
    reg [10:0] remainder;
    reg [9:0] divisor;
    wire [9:0] offset=adc_sample-adc_min;
    wire [10:0] shifted={remainder[9:0],quotient[19]};
    wire subtract=shifted>={1'b0,divisor};
    wire [10:0] remainder_next=subtract ? shifted-{1'b0,divisor} : shifted;
    wire [19:0] quotient_next={quotient[18:0],subtract};
    reg [19:0] depth_product;
    wire [9:0] triangle=lfo[12] ? ~lfo[11:2] : lfo[11:2];
    wire valid=seen && age<4883 && !adc_timeout;
    assign position=code;
    assign available=valid && mode!=0;
    wire [12:0] manual_gain={volume,8'd0};
    wire [12:0] slider_gain=code==1023 ? 13'd4096 : {1'b0,code,2'd0};
    wire [15:0] slider_pitch=code==1023 ? 16'hffff : 16'd32768+{1'b0,code,5'd0};
    // One-sided downward vibrato around the current pressure pitch base.
    wire [15:0] vibrato_delta={5'd0,depth_product[19:9]};
    wire [15:0] vibrato_pitch=(pressure_pitch>vibrato_delta) ? pressure_pitch-vibrato_delta : 16'd32768;
    assign master_gain=(mode==1 && valid && slider_gain<manual_gain) ? slider_gain : manual_gain;
    assign pitch_ratio=mode==2 ? (valid ? slider_pitch : pressure_pitch) :
                       mode==3 ? (valid ? vibrato_pitch : pressure_pitch) :
                       pressure_pitch;
    assign effect_wet=(mode==4 && valid) ? (code==1023 ? 4'd8 : {1'b0,code[9:7]}) : wet;
    always @(posedge clk)begin
        if(!resetn)begin code<=0;age<=4883;lfo<=0;seen<=0;depth_product<=0;converting<=0;divide_left<=0;quotient<=0;remainder<=0;divisor<=1;end
        else begin
            if(adc_valid)begin
                age<=0;
                if(adc_sample<=adc_min)begin code<=0;seen<=1;converting<=0;end
                else if(adc_sample>=adc_max)begin code<=1023;seen<=1;converting<=0;end
                else begin
                    quotient<=({10'd0,offset}<<10)-offset;remainder<=0;
                    divisor<=adc_max-adc_min;divide_left<=19;converting<=1;
                end
            end
            else if(frame_ce && age<4883)age<=age+1'b1;
            if(converting && !adc_valid)begin
                quotient<=quotient_next;remainder<=remainder_next;
                if(divide_left==0)begin code<=quotient_next[9:0];seen<=1;converting<=0;end
                else divide_left<=divide_left-1'b1;
            end
            if(frame_ce)lfo<=lfo+1'b1;
            depth_product<=triangle*code;
        end
    end
endmodule
