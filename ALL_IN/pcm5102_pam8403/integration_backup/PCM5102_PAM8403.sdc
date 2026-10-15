# Every internal sequential element uses the board 50 MHz clock.
create_clock -name clk -period 20.000 [get_ports {clk}]
# S1 is asynchronous: exclude only its path to the FIRST synchronizer FF.
set_false_path -from [get_ports {key_s1}] -to [get_pins {u_string/key_meta*/D}]
# BCK/LRCK/DIN are registered outputs, not clocks for internal logic.
# This master-clock constraint does not model cable / DAC output timing.
