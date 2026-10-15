# All internal logic uses the 50 MHz board clock.
create_clock -name clk -period 20.000 [get_ports {clk}]
# Exclude asynchronous inputs only up to the FIRST synchronization register.
set_false_path -from [get_ports {key_s1}] -to [get_pins {u_s1/key_meta*/D}]
set_false_path -from [get_ports {key_s2}] -to [get_pins {u_s2/key_meta*/D}]
# DAC cable/setup timing is checked separately by the exported I2S waveforms.
