create_clock -name clk -period 20.000 [get_ports {CLK_IN}]
# SDO is asynchronous. Exclude ONLY the first synchronizer input.
set_false_path -from [get_ports {touch_sdo}] -to [get_pins {u_touch/sdo_meta*/D}]
# The second synchronizer stage and all fabric paths stay timed at 50 MHz.
# Cable/output timing is checked from protocol pulse widths, not this SDC.
