create_clock -name clk -period 20.000 [get_ports {CLK_IN}]
set_false_path -from [get_ports {hc05_rx}] -to [get_pins {u_uart/rx_meta*/D}]
# All logic after the first synchronizer stage remains timed at 50 MHz.
