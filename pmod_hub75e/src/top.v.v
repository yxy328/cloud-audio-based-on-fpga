/***********************************************
64x64 = 8192 Byte
5bit per color, 15bit per pixel
2pix in a 32bit Word: R1G1B1 in 0th line, R2G2B2 in 32th line

***********************************************/
`define ROW_CNT      16'd32  //32x2
`define ROW_BITS      6'd5 

`define COL_CNT      16'd64   //64
`define COL_BITS      6'd6     //6
`define COL_CNT_FULL 16'd64   
`define COL_CNT_REST 16'd0   //COLS补齐到次幂的数量
//ram_addr 存储按次幂对齐

`define PWM_BITS      6'd5

/*
from PIL import Image
import numpy as np
im = Image.open("S.bmp")
img = np.array(im)
shape=img.shape
print("#File_format=Hex")
print("#Address_depth=%d"%(shape[0]*shape[1]/2))
print("#Data_width=32")
for y in range(32):
    for x in range(shape[1]):
        rgb1 = (img[y,x,2]>>3)|((img[y,x,1]>>3)<<5)|((img[y,x,0]>>3)<<10)
        rgb2 = (img[y+32,x,2]>>3)|((img[y+32,x,1]>>3)<<5)|((img[y+32,x,0]>>3)<<10)
        print("%04X%04X"%(rgb1, rgb2))
*/

module TOP #(
    parameter TTP_ACTIVE_LOW = 1,
    parameter TTP_STARTUP_US = 600000,
    parameter S2_DEBOUNCE_MS = 20,
    parameter S2_TOGGLE_MODE = 1,
    parameter TTP_GPIO_ACTIVE_LOW = 0,
    parameter TTP_GPIO_DEBOUNCE_MS = 20
) (
	       input wire 	 CLK_IN,  //OSC : E2
	       input wire 	 USER_KEY,//S1  : H11, active-high when pressed
           input wire    S2,       // H10: confirmed press toggles 8/16 keys
	       output wire 	 hub_R1,  //G10
	       output wire 	 hub_G1,  //G11
	       output wire 	 hub_B1,  //D10
	       output wire 	 hub_R2,  //B10
	       output wire 	 hub_G2,  //B11
	       output wire 	 hub_B2,  //C10
	       output wire 	 hub_E,   //C11
	       output wire 	 hub_A,   //A10
	       output wire 	 hub_B,   //A11
	       output wire 	 hub_C,   //E10
	       output wire 	 hub_D,   //E11
	       output wire 	 hub_CK,  //L11
	       output wire 	 hub_ST,  //K11
	       output wire 	 hub_OE,  //K5
           output wire 	 dbg0,    //K2
           output wire 	 dbg1,    //L1
           output wire 	 dbg2,    //K4
           output wire   touch_scl, //F6: 40Pin SDRAM A0, 3.3V
           input  wire   touch_sdo, //F7: 40Pin SDRAM A1, pull-up
           input  wire [7:0] touch_out // OUT1..8 direct inputs for mode_16=0
);

   // Power-on reset and active-high S1 on the Tang Primer 25K Dock.
   reg [5:0] reset_cnt = 0;
   wire      presetn = &reset_cnt;
   reg 	     uresetn = 0;
   wire      resetn = presetn & uresetn;

   always @(posedge CLK_IN) begin
      reset_cnt <= reset_cnt + !presetn;
      uresetn <= ~USER_KEY;
   end

   wire   scan_clock;
   // Dedicated GAO sample clock: 50MHz / 16 = 3.125MHz.
   // Keep this net even when building without an inserted analyzer.
   (* syn_keep = 1 *) wire clock;
   // Retain the example's actual scan clock: 50MHz / 2 = 25MHz.
   (* syn_preserve = 1, syn_keep = 1 *) reg [5:0] clkn = 0;
   (* syn_preserve = 1, syn_keep = 1 *) reg scan_div = 0;
   // Keep the analyzer clock alive so it can observe an asserted reset.
   always @(posedge CLK_IN) begin
      clkn <= clkn + 6'd1;
      // Preserve the panel/ROM divider's reset phase and first read edge.
      if (!resetn)
        scan_div <= 1'b0;
      else
        scan_div <= ~scan_div;
   end
   assign scan_clock = scan_div;
   assign clock = clkn[3];


   wire [`ROW_BITS+`COL_BITS-1:0] ram_raddr;
   wire [15:0] ram_rdata1;
   wire [15:0] ram_rdata2;


   wire frame_clk;
   wire [15:0] touch_keys;
   wire touch_valid;
   wire [2:0] touch_state;
   wire [3:0] touch_bit_cnt;
   wire [15:0] keys_stable;
   wire [15:0] key_press;
   wire image_requested;
   wire [3:0] brightness_requested;
   wire [15:0] serial_keys;
   wire serial_valid;
   wire [7:0] gpio_keys_raw;
   wire [7:0] gpio_keys_stable;
   wire gpio_valid;
   wire touch_ready;
   (* syn_keep = 1 *) wire mode_16;
   // Internal falling-edge snapshots avoid GAO's port-alias routing issue.
   // [0] SCL, [1] SDO, [2] S1, [3] mode, [4] S2, [7:5] reader FSM,
   // [11:8] reader bit index.
   (* syn_preserve = 1, syn_keep = 1 *) reg [11:0] gao_mode_probe = 12'd0;
   always @(negedge CLK_IN)
       gao_mode_probe <= {touch_bit_cnt, touch_state, S2, mode_16, USER_KEY, touch_sdo, touch_scl};
   wire mode_changed;
   // Electrical OUT inputs and debounced direct keys for GAO.
   (* syn_preserve = 1, syn_keep = 1 *) reg [25:0] gao_gpio_probe = 26'd0;
   always @(negedge CLK_IN)
       gao_gpio_probe <= {gpio_valid, touch_ready, gpio_keys_stable, gpio_keys_raw, touch_out};
   ttp229_mode_select #(
       .DEBOUNCE_MS(S2_DEBOUNCE_MS), .TOGGLE_MODE(S2_TOGGLE_MODE)
   ) mode_select (
       .clk(CLK_IN), .resetn(resetn), .s2(S2),
       .mode_16(mode_16), .mode_changed(mode_changed), .state_o()
   );

   // mode_16=0: OUT1..OUT8 direct input; mode_16=1: 16-key serial.
   // Both feed the same UI and HUB75E display. Wiring is changed manually.
   ttp229_gpio_input #(
       .STARTUP_US(TTP_STARTUP_US), .DEBOUNCE_MS(TTP_GPIO_DEBOUNCE_MS),
       .ACTIVE_LOW(TTP_GPIO_ACTIVE_LOW)
   ) gpio_touch (
       .clk(CLK_IN), .resetn(resetn), .enable(!mode_16 && !mode_changed),
       .touch_out(touch_out), .keys_raw(gpio_keys_raw), .keys_stable(gpio_keys_stable),
       .sample_valid(gpio_valid), .ready(touch_ready)
   );

   // TTP229-BSF / HW-136 configuration expected by this project:
   // TP2 must match S2: open for 8 keys, shorted for 16 keys.
   // Power-cycle after changing jumpers. SDO is active-low by default.
   // SCL=F6, SDO=F7, both in a 3.3V bank. touch_keys[0] is key 1.
   ttp229_ctrl #(
       .CLK_FREQ(50_000_000), .KEY_NUM(16), .TP_ACTIVE_LOW(TTP_ACTIVE_LOW),
       .SCL_HALF_US(50), .VALID_PULSE_US(20), .STARTUP_US(TTP_STARTUP_US),
       .ENABLE_CONTROL(1)
   ) touch_ctrl (
       .clk(CLK_IN), .resetn(resetn), .sdo(touch_sdo), .scl(touch_scl),
       .touch_valid(serial_valid), .touch_keys(serial_keys),
       .state_o(touch_state), .bit_cnt_o(touch_bit_cnt),
       .mode_16(1'b1), .enable(mode_16 && touch_ready && !mode_changed)
   );
   assign touch_keys = mode_16 ? serial_keys : {8'd0, gpio_keys_stable};
   assign touch_valid = mode_16 ? serial_valid : gpio_valid;

   // GPIO already has independent 20ms debounce; UI confirms three 1ms
   // samples. Serial mode confirms three complete frames. One event/press.
   // K1=S, K2=T; GPIO K7/K8 or serial K15/K16 are minus/plus.
   touch_ui #(.STABLE_FRAMES(3), .MODE_CONTROL(1)) touch_actions (
       .clk(CLK_IN), .resetn(resetn), .touch_valid(touch_valid),
       .touch_keys(touch_keys), .keys_stable(keys_stable),
       .key_press(key_press), .image_sel(image_requested),
       .brightness(brightness_requested), .clear_keys(mode_changed), .mode_16(mode_16)
   );
   assign dbg0 = touch_keys[0];
   assign dbg1 = touch_keys[1];
   assign dbg2 = touch_valid;

   reg image_active;
   reg [3:0] brightness_active;
   display_rom logo_rom(
        .dout({ram_rdata1, ram_rdata2}), 
        .clk(scan_clock), 
        .reset(!resetn), 
        .ad(ram_raddr),
        .image_sel(image_active));

   // Generate IF signals
   wire [`ROW_BITS-1:0] rows; 
   assign { hub_E, hub_D, hub_C, hub_B, hub_A } = rows;
 
   hub75e_if hubif(scan_clock, resetn, rows, hub_CK, hub_ST, hub_OE, ram_raddr, frame_clk);

   // One frame_clk rising edge means one row latch, not a whole image.
   // Keep control registers on CLK_IN. frame_clk is derived from CLK_IN
   // and stays high for several master clocks, so its edge is not missed.
   reg [`PWM_BITS+`ROW_BITS-1:0] frame_count;
   reg frame_clk_d;
   wire row_latched = frame_clk & ~frame_clk_d;
   wire pwm_cycle_end = row_latched & (&frame_count);
   always @(posedge CLK_IN) begin
      if (!resetn) begin
        frame_count       <= 0;
        frame_clk_d       <= 0;
        image_active      <= 1'b0; // logoT, same startup image as example
        brightness_active <= 4'd8; // full brightness, original 5-bit PWM
      end
      else begin
        frame_clk_d <= frame_clk;
        if (row_latched)
          frame_count <= frame_count + 1'b1;
        // All 32 rows at all 32 PWM phases finish before committing.
        // The last row is already shifted; the latch/blank interval gives
        // both ROMs time to provide row 0 before the next scan begins.
        if (pwm_cycle_end) begin
          image_active      <= image_requested;
          brightness_active <= brightness_requested;
        end
      end
   end

   // 8 brightness steps: floor(color * level / 8), then the same 32-phase
   // comparison as the example. At level 8 every color is unchanged.
   // Scale each channel independently so brightness preserves the image.
   function [4:0] scale_color;
     input [4:0] color;
     input [3:0] level;
     reg [8:0] product;
     begin
       product = color * level;
       scale_color = product[7:3];
     end
   endfunction
   wire [4:0] threshold = frame_count[`PWM_BITS+`ROW_BITS-1:`ROW_BITS];

   // No LED panel is required to observe this debug snapshot in GAO.
   // [15:0] raw keys, [31:16] debounced keys, [32] requested image,
   // [36:33] requested brightness, [37] active image,
   // [41:38] active brightness, [42] frame valid, [43] key-change trigger.
   // The trigger lasts 20us; the 20ns key_press pulse is too short for GAO.
   (* syn_keep = 1 *) wire [43:0] gao_probe;
   gao_touch_debug touch_debug (
       .clk(CLK_IN), .resetn(resetn), .touch_keys(touch_keys),
       .keys_stable(keys_stable), .touch_valid(touch_valid),
       .image_requested(image_requested), .brightness_requested(brightness_requested),
       .image_active(image_active), .brightness_active(brightness_active),
       .gao_probe(gao_probe)
   );
   
   assign hub_R1 = (scale_color(ram_rdata1[14:10], brightness_active) > threshold);
   assign hub_G1 = (scale_color(ram_rdata1[ 4: 0], brightness_active) > threshold);
   assign hub_B1 = (scale_color(ram_rdata1[ 9: 5], brightness_active) > threshold);
   assign hub_R2 = (scale_color(ram_rdata2[14:10], brightness_active) > threshold);
   assign hub_G2 = (scale_color(ram_rdata2[ 4: 0], brightness_active) > threshold);
   assign hub_B2 = (scale_color(ram_rdata2[ 9: 5], brightness_active) > threshold);


endmodule // hub75e

// Actual top-level scan clock is 25MHz (scan_div).
// 64 shift clocks + 3 latch/blank clocks = 67 clocks per row.
//rows -> ABCDE

module hub75e_if (
		  input 	clk,
		  input 	resetn,
		  output [`ROW_BITS-1:0] 	     rows,  //5bit, 32line
		  output     hub_ck,     //CLK
		  output     hub_st,     //LAT
		  output reg hub_oe,     //OE
		  output [`ROW_BITS+`COL_BITS-1:0] ram_addr,//2048x32bit
		  output reg frame_clk   // L shift, H store
);
   localparam [1:0] S_SHIFT = 2'd0;
   localparam [1:0] S_LATCH = 2'd1;
   localparam [1:0] S_BLANK = 2'd2;
   localparam [1:0] S_PRIME = 2'd3;

   reg [`ROW_BITS+`COL_BITS-1:0] hub_addr;
   reg [`ROW_BITS-1:0] display_row;
   reg [1:0] state;
   reg last_pixel;
   reg have_latched;
   // Gowin FPGA power-up values also cover resetn already low at time 0,
   // before the first divided-clock edge has initialized this logic.
   initial begin
      state        = S_PRIME;
      hub_addr     = 0;
      display_row  = 0;
      frame_clk    = 0;
      hub_oe       = 1;
      last_pixel   = 0;
      have_latched = 0;
   end
   assign ram_addr = hub_addr;
   // Gating changes only at the falling edge. PRIME supplies synchronous
   // pROM data before the first CK; only SHIFT produces external clocks.
   assign hub_ck = clk & (state == S_SHIFT) & resetn;
   assign hub_st = clk & (state == S_LATCH) & resetn;
   assign rows = display_row;

   // Reset also acts between scan-clock edges. Keep the panel blank
   // until a row is ready after reset is released.
   always @(negedge clk or negedge resetn) begin
      if (!resetn) begin
         state        <= S_PRIME;
         hub_addr     <= 0;
         display_row  <= 0;
         frame_clk    <= 0;
         hub_oe       <= 1;
         last_pixel   <= 0;
         have_latched <= 0;
      end
      else begin
         case (state)
            S_PRIME: begin
               // The preceding rising edge read column 0. Present column
               // 1 to pROM while the next rising CK shifts column 0.
               hub_addr <= hub_addr + 1'b1;
               last_pixel <= 0;
               hub_oe <= !have_latched;
               state <= S_SHIFT;
            end
            S_SHIFT: begin
               if (last_pixel) begin
                  // Column 63 was just shifted. RGB / image changes are
                  // now safe: blank, select the row, then issue one LAT.
                  hub_oe <= 1;
                  display_row <= hub_addr[`ROW_BITS+`COL_BITS-1:`COL_BITS];
                  frame_clk <= 1;
                  have_latched <= 1;
                  state <= S_LATCH;
               end
               else if (hub_addr[`COL_BITS-1:0] == (`COL_CNT-1)) begin
                  // That rising CK shifted column 62; hold address 63
                  // for one final CK to consume its one-edge ROM result.
                  last_pixel <= 1;
               end
               else
                  hub_addr <= hub_addr + 1'b1;
            end
            S_LATCH: begin
               frame_clk <= 0;
               state <= S_BLANK;
            end
            S_BLANK: begin
               // Wrap 31/63 to 0/0 automatically at the 11-bit width.
               hub_addr <= hub_addr + 1'b1;
               state <= S_PRIME;
            end
            default: begin
               state <= S_PRIME;
               hub_addr <= 0;
               frame_clk <= 0;
               hub_oe <= 1;
               last_pixel <= 0;
               have_latched <= 0;
            end
         endcase
      end
   end

endmodule // hub75e_if

/*
module pixram (
	       input wire 	 clk,
	       input wire 	 read,
	       input wire 	 write,
	       input wire [ROW_BITS+COL_BITS-1:0] raddr,
	       input wire [ROW_BITS+COL_BITS-1:0] waddr,
	       output reg [31:0] data_out,
	       input wire [31:0] data_in
);

   reg [31:0] 			 mem[0:COL_CNT_FULL*ROW_CNT-1];

   always @(posedge clk) begin
      if (write) begin
         mem[waddr] <= data_in;
      end
      if (read) begin
	 data_out <= mem[raddr];
      end
   end // always @ (posedge clk)

endmodule // pixram */





