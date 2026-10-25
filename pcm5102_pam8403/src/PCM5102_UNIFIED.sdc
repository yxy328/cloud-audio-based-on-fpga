# Pedal target retains event Flash storage on the 50MHz fabric clock.
create_clock -name clk -period 20.000 [get_ports {clk}]
create_generated_clock -name fsr_adc_clk -source [get_ports {clk}] -divide_by 20 [get_pins {u_main/u_fsr_adc/adc_inst/CLK}]
set_false_path -from [get_ports {key_s1}] -to [get_pins {u_main/u_s1/key_meta*/D}]
set_false_path -from [get_ports {key_s2}] -to [get_pins {u_main/u_s2/key_meta*/D}]
set_false_path -from [get_ports {touch_out[*]}] -to [get_pins {u_main/u_touch_input/input_meta*/D}]
set_false_path -from [get_ports {touch_out[7]}] -to [get_pins {u_main/u_touch_mode_input/input_meta*/D}]
set_false_path -from [get_ports {hc05_rx}] -to [get_pins {u_main/u_keymap/u_uart/rx_meta*/D}]
set_false_path -from [get_ports {sda}] -to [get_pins {u_main/u_gesture/u_i2c/sda_meta*/D}]
set_false_path -from [get_ports {slider_sda}] -to [get_pins {u_main/u_slider_adc/u_i2c/sda_meta*/D}]
set_false_path -from [get_ports {ir_beam[*]}] -to [get_pins {u_main/u_ir/beam_meta*/D}]
set_false_path -from [get_ports {touch_sdo}] -to [get_pins {u_main/u_touch_serial/sdo_meta*/D}]

set_false_path -from [get_ports {flash_miso}] -to [get_pins {u_main/take_enabled.u_store/internal_spi.u_spi/miso_meta*/D}]
