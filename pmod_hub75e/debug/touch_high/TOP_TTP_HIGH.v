`timescale 1ns/1ps

// Software polarity comparison: keep the same pinout and design, but read
// an active-high TTP229 with idle-low SCL and active-high SDO decoding.
module TOP_TTP_HIGH (
    input wire CLK_IN,
    input wire USER_KEY,
    input wire S2,
    input wire [7:0] touch_out,
    output wire hub_R1,
    output wire hub_G1,
    output wire hub_B1,
    output wire hub_R2,
    output wire hub_G2,
    output wire hub_B2,
    output wire hub_E,
    output wire hub_A,
    output wire hub_B,
    output wire hub_C,
    output wire hub_D,
    output wire hub_CK,
    output wire hub_ST,
    output wire hub_OE,
    output wire dbg0,
    output wire dbg1,
    output wire dbg2,
    output wire touch_scl,
    input wire touch_sdo
);
    TOP #(.TTP_ACTIVE_LOW(0)) dut (
        .CLK_IN(CLK_IN), .USER_KEY(USER_KEY), .S2(S2), .touch_out(touch_out),
        .hub_R1(hub_R1), .hub_G1(hub_G1), .hub_B1(hub_B1),
        .hub_R2(hub_R2), .hub_G2(hub_G2), .hub_B2(hub_B2),
        .hub_E(hub_E), .hub_A(hub_A), .hub_B(hub_B),
        .hub_C(hub_C), .hub_D(hub_D),
        .hub_CK(hub_CK), .hub_ST(hub_ST), .hub_OE(hub_OE),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2),
        .touch_scl(touch_scl), .touch_sdo(touch_sdo)
    );
endmodule
