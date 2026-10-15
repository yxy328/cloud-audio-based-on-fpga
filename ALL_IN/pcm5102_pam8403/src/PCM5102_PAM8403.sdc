create_clock -name clk -period 20.000 [get_ports {clk}]
set_false_path -from [get_ports {key_s1}] -to [get_pins {u_string/key_meta*/D}]
set_false_path -from [get_ports {key_s2}] -to [get_pins {u_gesture/u_audio/tone_meta*/D}]
set_false_path -from [get_ports {touch_out[*]}] -to [get_pins {u_touch_input/meta*/D u_touch_mode_input/meta*/D}]

