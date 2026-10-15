`timescale 1ns/1ps
// Behavioral ADC interface model. This models conversion timing/handshake,
// not the analog transfer function, noise, pin mux, or actual ADC calibration.
module ADC #(
    parameter CLK_SEL=1'b1, DIV_CTL=2'd0, BUF_EN=12'd0,
    parameter BUF_BK0_VREF_EN=0, BUF_BK1_VREF_EN=0, BUF_BK2_VREF_EN=0,
    parameter BUF_BK3_VREF_EN=0, BUF_BK4_VREF_EN=0, BUF_BK5_VREF_EN=0,
    parameter BUF_BK6_VREF_EN=0, BUF_BK7_VREF_EN=0,
    parameter CSR_ADC_MODE=1'b1, CSR_VSEN_CTRL=3'd0,
    parameter CSR_SAMPLE_CNT_SEL=3'd4, CSR_RATE_CHANGE_CTRL=3'd4,
    parameter CSR_FSCAL=10'd653, CSR_OFFSET=12'd0
) (
    input wire CLK, input wire [2:0] VSENCTL, input wire ADCMODE,
    input wire DRSTN, input wire ADCREQI, input wire ADCEN,
    input wire MDRP_CLK, input wire [7:0] MDRP_WDATA,
    input wire MDRP_A_INC, input wire [1:0] MDRP_OPCODE,
    output wire [7:0] MDRP_RDATA,
    output reg ADCRDY=0, output reg [13:0] ADCVALUE=0
);
    // Testbench supplies the expected voltage code (volts*2048).
    reg [13:0] sim_value=0;
    reg [13:0] pending=0;
    reg previous_request=0, converting=0;
    integer cycles=0,conversions=0;
    localparam CONVERSION_CYCLES=(64<<CSR_SAMPLE_CNT_SEL)+20;
    assign MDRP_RDATA=0;
    initial begin
        if(CLK_SEL!==1 || DIV_CTL!=0 || BUF_EN!=0 || CSR_ADC_MODE!=1 ||
           CSR_VSEN_CTRL!=0 || CSR_SAMPLE_CNT_SEL!=4 || CSR_RATE_CHANGE_CTRL!=4 ||
           CSR_FSCAL!=653 || CSR_OFFSET!=0)
            $fatal(1,"On-chip ADC configuration differs from PAD voltage mode");
    end
    always @(posedge CLK or negedge DRSTN) begin
        if(!DRSTN) begin
            ADCRDY<=0;ADCVALUE<=0;previous_request<=0;
            converting<=0;cycles<=0;conversions<=0;
        end else begin
            previous_request<=ADCREQI;
            if(ADCEN && ADCREQI && !previous_request) begin
                ADCRDY<=0;pending<=sim_value;cycles<=0;converting<=1;
            end else if(converting) begin
                if(cycles==CONVERSION_CYCLES-1) begin
                    ADCVALUE<=pending;ADCRDY<=1;converting<=0;
                    conversions<=conversions+1;
                end else cycles<=cycles+1;
            end
        end
    end
endmodule
