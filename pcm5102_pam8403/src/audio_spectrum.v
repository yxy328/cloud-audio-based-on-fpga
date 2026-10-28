`timescale 1ns/1ps
// Observer only: CIC3 /8 anti-alias decimation, Hann window, 256-point FFT.
// Fs=6103.515625Hz, bin spacing=23.8418579Hz. The in-place radix-2 FFT
// shares ONE registered signed multiplier; each butterfly scales by 1/2.
// One 1024x16 RAM holds 256 complex samples and 128 complex twiddle constants.
// Real/imaginary words are serialized to retain the device's SDP16 mapping.
module audio_spectrum (
    input wire clk, resetn, sample_ce,
    input wire signed [15:0] sample,
    output reg [79:0] levels,
    output reg valid, done,
    output reg [7:0] peak_bin,
    output reg [16:0] peak_magnitude
);
    reg signed [24:0] integ1,integ2,integ3,delay1,delay2,delay3,comb1,comb2;
    reg [2:0] dec_count,warmup;
    reg filtered_valid;
    reg signed [15:0] filtered;
    wire signed [24:0] sample_wide={{9{sample[15]}},sample};
    wire signed [24:0] comb_result=comb2-delay3;
    always @(posedge clk) begin
        if(!resetn) begin
            integ1<=0;integ2<=0;integ3<=0;delay1<=0;delay2<=0;delay3<=0;
            comb1<=0;comb2<=0;dec_count<=0;warmup<=0;filtered<=0;filtered_valid<=0;
        end else begin
            filtered_valid<=0;
            if(sample_ce) begin
                integ1<=integ1+sample_wide;integ2<=integ2+integ1;integ3<=integ3+integ2;
                dec_count<=dec_count+1'b1;
                if(dec_count==7) begin
                    comb1<=integ3-delay1;delay1<=integ3;
                    comb2<=comb1-delay2;delay2<=comb1;delay3<=comb2;
                    filtered<=comb_result[24:9];
                    if(warmup==7) filtered_valid<=1;
                    else warmup<=warmup+1'b1;
                end
            end
        end
    end

    (* syn_ramstyle="block_ram" *) reg [15:0] memory[0:1023];
    initial $readmemh("src/fft256_init.hex",memory);
    reg [15:0] ram_q;
    reg [9:0] read_address;
    always @(posedge clk) ram_q<=memory[read_address];
    localparam CAPTURE=0,COS_READ=1,WINDOW_MUL=2,WINDOW_WAIT=3,CAP_WRITE=4,
        READ_U=5,LOAD_U=6,READ_V=7,LOAD_V=8,READ_W=9,LOAD_W=10,
        M0_WAIT=11,M0_LOAD=12,M1_WAIT=13,M1_LOAD=14,
        M2_WAIT=15,M2_LOAD=16,M3_WAIT=17,M3_LOAD=18,
        WRITE_U=19,WRITE_V=20,MAG_READ=21,MAG_LOAD=22,PUBLISH=23,
        READ_UI=24,LOAD_UI=25,READ_VI=26,LOAD_VI=27,READ_WI=28,LOAD_WI=29,
        CAP_WRITE_IMAG=30,MAG_I_READ=31,MAG_I_LOAD=32,WRITE_UI=33,WRITE_VI=34,
        MAG_SCALE=35,MAG_ACCUMULATE=36;
    reg [5:0] state;
    reg [7:0] capture_index,half_size,stride,base,offset,twiddle_index,mag_index;
    reg signed [15:0] captured,u_real,u_imag,v_real,v_imag,w_real,w_imag;
    reg signed [15:0] mul_a,mul_b;
    reg signed [31:0] product,partial_real,partial_imag;
    reg signed [32:0] rotated_real,rotated_imag;
    reg [79:0] working_levels;
    reg [7:0] working_peak_bin;
    reg [16:0] working_peak;
    reg [15:0] mag_real;
    reg [16:0] bin_magnitude;
    reg [4:0] bar_height;
    wire [7:0] u_address=base+offset;
    wire [7:0] v_address=u_address+half_size;
    wire [8:0] next_base={1'b0,base}+{half_size,1'b0};
    wire [7:0] cosine_index=capture_index[7] ? -capture_index : capture_index;
    wire [7:0] reversed_index={capture_index[0],capture_index[1],capture_index[2],capture_index[3],
        capture_index[4],capture_index[5],capture_index[6],capture_index[7]};
    wire signed [16:0] window_delta=17'sd32767-$signed({ram_q[15],ram_q});
    always @* begin
        read_address=0;
        case(state)
            COS_READ: read_address={1'b1,cosine_index,1'b0};
            READ_U,LOAD_U: read_address={1'b0,u_address,1'b0};
            READ_UI,LOAD_UI: read_address={1'b0,u_address,1'b1};
            READ_V,LOAD_V: read_address={1'b0,v_address,1'b0};
            READ_VI,LOAD_VI: read_address={1'b0,v_address,1'b1};
            READ_W,LOAD_W: read_address={1'b1,twiddle_index,1'b0};
            READ_WI,LOAD_WI: read_address={1'b1,twiddle_index,1'b1};
            MAG_READ,MAG_LOAD: read_address={1'b0,mag_index,1'b0};
            MAG_I_READ,MAG_I_LOAD: read_address={1'b0,mag_index,1'b1};
        endcase
    end
    always @(posedge clk) product<=mul_a*mul_b;
    wire signed [17:0] tr=rotated_real[32:15],ti=rotated_imag[32:15];
    wire positive_butterfly=state==WRITE_U || state==WRITE_UI;
    wire signed [18:0] result_real=positive_butterfly ?
        ($signed({{3{u_real[15]}},u_real})+$signed({tr[17],tr})) :
        ($signed({{3{u_real[15]}},u_real})-$signed({tr[17],tr}));
    wire signed [18:0] result_imag=positive_butterfly ?
        ($signed({{3{u_imag[15]}},u_imag})+$signed({ti[17],ti})) :
        ($signed({{3{u_imag[15]}},u_imag})-$signed({ti[17],ti}));
    function [15:0] scaled;
        input signed [18:0] value;
        reg signed [18:0] shifted;
        begin
            shifted=value>>>1;
            scaled=shifted>32767 ? 16'h7fff : shifted < -32768 ? 16'h8000 : shifted[15:0];
        end
    endfunction
    function [15:0] magnitude16;
        input [15:0] value;
        begin magnitude16=value[15] ? (~value+16'd1) : value; end
    endfunction
    wire [16:0] magnitude={1'b0,magnitude16(mag_real)}+{1'b0,magnitude16(ram_q)};
    function [3:0] band_for;
        input [7:0] bin;
        begin
            if(bin<4) band_for=0; else if(bin<6) band_for=1;
            else if(bin<8) band_for=2; else if(bin<10) band_for=3;
            else if(bin<12) band_for=4; else if(bin<14) band_for=5;
            else if(bin<16) band_for=6; else if(bin<19) band_for=7;
            else if(bin<22) band_for=8; else if(bin<26) band_for=9;
            else if(bin<32) band_for=10; else if(bin<40) band_for=11;
            else if(bin<50) band_for=12; else if(bin<64) band_for=13;
            else if(bin<88) band_for=14; else band_for=15;
        end
    endfunction
    function [4:0] height_for;
        input [16:0] value;
        integer bit_number;
        reg [5:0] height;
        begin
            height=0;
            for(bit_number=0;bit_number<17;bit_number=bit_number+1)
                if(value[bit_number]) height=bit_number*2+1;
            if(value<=8) height=0; // Suppress the fixed-point FFT's few-LSB floor.
            height_for=height>31 ? 5'd31 : height[4:0];
        end
    endfunction
    wire [3:0] band=band_for(mag_index);
    // Read the selected band's previous height during the existing scaling
    // cycle. Accumulation compares two registered heights; its write enable
    // no longer includes the 80-bit bank read mux. No FFT cycle is added.
    reg [4:0] previous_height;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=CAPTURE;capture_index<=0;half_size<=1;stride<=128;base<=0;offset<=0;twiddle_index<=0;mag_index<=1;
            captured<=0;u_real<=0;u_imag<=0;v_real<=0;v_imag<=0;w_real<=0;w_imag<=0;
            mul_a<=0;mul_b<=0;partial_real<=0;partial_imag<=0;rotated_real<=0;rotated_imag<=0;
            levels<=0;working_levels<=0;valid<=0;done<=0;peak_bin<=0;peak_magnitude<=0;working_peak<=0;working_peak_bin<=0;
            mag_real<=0;bin_magnitude<=0;bar_height<=0;
        end else begin
            done<=0;
            case(state)
                CAPTURE:if(filtered_valid) begin captured<=filtered;state<=COS_READ;end
                COS_READ:state<=WINDOW_MUL;
                WINDOW_MUL:begin
                    mul_a<=captured;mul_b<=capture_index==128 ? 16'sd32767 : $signed(window_delta[16:1]);state<=WINDOW_WAIT;
                end
                WINDOW_WAIT:state<=CAP_WRITE;
                CAP_WRITE:begin
                    memory[{1'b0,reversed_index,1'b0}]<=product[30:15];state<=CAP_WRITE_IMAG;
                end
                CAP_WRITE_IMAG:begin
                    memory[{1'b0,reversed_index,1'b1}]<=0;
                    capture_index<=capture_index+1'b1;
                    if(capture_index==255) begin
                        half_size<=1;stride<=128;base<=0;offset<=0;twiddle_index<=0;
                        working_levels<=0;working_peak<=0;working_peak_bin<=0;state<=READ_U;
                    end else state<=CAPTURE;
                end
                READ_U:state<=LOAD_U;
                LOAD_U:begin u_real<=ram_q;state<=READ_UI;end
                READ_UI:state<=LOAD_UI;
                LOAD_UI:begin u_imag<=ram_q;state<=READ_V;end
                READ_V:state<=LOAD_V;
                LOAD_V:begin v_real<=ram_q;state<=READ_VI;end
                READ_VI:state<=LOAD_VI;
                LOAD_VI:begin v_imag<=ram_q;state<=READ_W;end
                READ_W:state<=LOAD_W;
                LOAD_W:begin
                    w_real<=ram_q;state<=READ_WI;
                end
                READ_WI:state<=LOAD_WI;
                LOAD_WI:begin w_imag<=ram_q;mul_a<=v_real;mul_b<=w_real;state<=M0_WAIT;end
                M0_WAIT:state<=M0_LOAD;
                M0_LOAD:begin partial_real<=product;mul_a<=v_imag;mul_b<=w_imag;state<=M1_WAIT;end
                M1_WAIT:state<=M1_LOAD;
                M1_LOAD:begin
                    rotated_real<=$signed({partial_real[31],partial_real})-$signed({product[31],product});
                    mul_a<=v_real;mul_b<=w_imag;state<=M2_WAIT;
                end
                M2_WAIT:state<=M2_LOAD;
                M2_LOAD:begin partial_imag<=product;mul_a<=v_imag;mul_b<=w_real;state<=M3_WAIT;end
                M3_WAIT:state<=M3_LOAD;
                M3_LOAD:begin
                    rotated_imag<=$signed({partial_imag[31],partial_imag})+$signed({product[31],product});state<=WRITE_U;
                end
                WRITE_U:begin memory[{1'b0,u_address,1'b0}]<=scaled(result_real);state<=WRITE_UI;end
                WRITE_UI:begin memory[{1'b0,u_address,1'b1}]<=scaled(result_imag);state<=WRITE_V;end
                WRITE_V:begin
                    memory[{1'b0,v_address,1'b0}]<=scaled(result_real);state<=WRITE_VI;
                end
                WRITE_VI:begin
                    memory[{1'b0,v_address,1'b1}]<=scaled(result_imag);
                    state<=READ_U;
                    if(offset==half_size-1) begin
                        offset<=0;twiddle_index<=0;
                        if(next_base>=256) begin
                            base<=0;
                            if(half_size==128) begin mag_index<=1;state<=MAG_READ;end
                            else begin half_size<=half_size<<1;stride<=stride>>1;end
                        end else base<=next_base[7:0];
                    end else begin offset<=offset+1'b1;twiddle_index<=twiddle_index+stride;end
                end
                MAG_READ:state<=MAG_LOAD;
                MAG_LOAD:begin mag_real<=ram_q;state<=MAG_I_READ;end
                MAG_I_READ:state<=MAG_I_LOAD;
                MAG_I_LOAD:begin
                    bin_magnitude<=magnitude;state<=MAG_SCALE;
                end
                // Separate RAM -> abs/sum, height compression and per-band
                // max/enable decoding to keep each path within 50MHz.
                MAG_SCALE:begin previous_height<=working_levels[band*5 +: 5];bar_height<=height_for(bin_magnitude);state<=MAG_ACCUMULATE;end
                MAG_ACCUMULATE:begin
                    if(bar_height>previous_height) working_levels[band*5 +: 5]<=bar_height;
                    if(bin_magnitude>working_peak) begin working_peak<=bin_magnitude;working_peak_bin<=mag_index;end
                    if(mag_index==127) state<=PUBLISH;
                    else begin mag_index<=mag_index+1'b1;state<=MAG_READ;end
                end
                PUBLISH:begin
                    levels<=working_levels;peak_bin<=working_peak_bin;peak_magnitude<=working_peak;
                    valid<=1;done<=1;state<=CAPTURE;
                end
                default:state<=CAPTURE;
            endcase
        end
    end
endmodule
