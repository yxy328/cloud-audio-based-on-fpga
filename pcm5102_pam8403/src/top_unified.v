`timescale 1ns/1ps
// Unified performance, score, LED, PCM recording and event replay target.
// Event control uses HC-05 so all sixteen pads remain musical keys.
module top_unified #(
    parameter integer PEDAL_TAIL_MS=1200, DAMPER_MS=10
)(
    input wire clk,key_s1,key_s2,
    input wire [7:0] touch_out,ir_beam,
    input wire touch_sdo,hc05_rx,audio_rec_cts_n,
    output wire hc05_tx,audio_rec_tx,i2s_bck,i2s_lrck,i2s_din,touch_scl,
    inout wire scl,sda,
    output wire hub_R1,hub_G1,hub_B1,hub_R2,hub_G2,hub_B2,
    output wire hub_A,hub_B,hub_C,hub_D,hub_E,hub_CK,hub_ST,hub_OE,
    output wire flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n,
    input wire flash_miso
);
    // The PCM store is disabled to reserve routing and logic for live voices.
    top #(.ENABLE_FLASH_AUDIO(0),.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.ENABLE_USB_AUDIO_RECORD(0),
        .PEDAL_TAIL_MS(PEDAL_TAIL_MS),.DAMPER_MS(DAMPER_MS),.HC05_BAUD(9600)) u_main(
        .clk(clk),.key_s1(key_s1),.key_s2(key_s2),.touch_out(touch_out),.ir_beam(ir_beam),
        .touch_sdo(touch_sdo),.hc05_rx(hc05_rx),.hc05_tx(hc05_tx),.audio_rec_cts_n(audio_rec_cts_n),.audio_rec_tx(audio_rec_tx),
        .i2s_bck(i2s_bck),.i2s_lrck(i2s_lrck),.i2s_din(i2s_din),.touch_scl(touch_scl),.scl(scl),.sda(sda),
        .hub_R1(hub_R1),.hub_G1(hub_G1),.hub_B1(hub_B1),.hub_R2(hub_R2),.hub_G2(hub_G2),.hub_B2(hub_B2),
        .hub_A(hub_A),.hub_B(hub_B),.hub_C(hub_C),.hub_D(hub_D),.hub_E(hub_E),.hub_CK(hub_CK),.hub_ST(hub_ST),.hub_OE(hub_OE),
        .flash_cs_n(flash_cs_n),.flash_sck(flash_sck),.flash_mosi(flash_mosi),.flash_miso(flash_miso),
        .flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
endmodule
