# Fabric runs at 50MHz; the on-chip ADC uses a related 2.5MHz clock.
create_clock -name clk -period 20.000 [get_ports {clk}]
create_generated_clock -name fsr_adc_clk -source [get_ports {clk}] -divide_by 20 [get_pins {u_fsr_adc/adc_inst/CLK}]
# Buttons are asynchronous: exclude only the FIRST synchronization FF.
set_false_path -from [get_ports {key_s1}] -to [get_pins {u_s1/key_meta*/D}]
set_false_path -from [get_ports {key_s2}] -to [get_pins {u_s2/key_meta*/D}]
# Direct touch inputs are asynchronous; constrain the second stage normally.
set_false_path -from [get_ports {touch_out[*]}] -to [get_pins {u_touch_input/input_meta*/D}]
set_false_path -from [get_ports {touch_out[7]}] -to [get_pins {u_touch_mode_input/input_meta*/D}]
# UART is asynchronous: exclude only its first synchronizer, keep stage 2 timed.
set_false_path -from [get_ports {hc05_rx}] -to [get_pins {u_keymap/u_uart/rx_meta*/D}]
# I2C SDA is asynchronous; only the first of two synchronization FFs is excluded.
set_false_path -from [get_ports {sda}] -to [get_pins {u_gesture/u_i2c/sda_meta*/D}]
set_false_path -from [get_ports {ir_beam[*]}] -to [get_pins {u_ir/beam_meta*/D}]
# ADC ready is synchronized and its stable result bus is captured only after
# ready goes low then high. ADC/fabric clock paths remain normally constrained.
# BCK/LRCK/DIN are registered outputs, not clocks for internal logic.
# This master-clock constraint does not model cable / DAC output timing.

set_false_path -from [get_ports {touch_sdo}] -to [get_pins {u_touch_serial/sdo_meta*/D}]
# HC-05-only default: the optional USB recorder and its CTS synchronizer
# are removed at elaboration, so there is no CTS timing exception here.
