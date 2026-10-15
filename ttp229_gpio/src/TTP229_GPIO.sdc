# Board crystal, 50 MHz.
create_clock -name CLK_IN -period 20.000 [get_ports {CLK_IN}]
# GAO only: free-running divide-by-256 clock, with falling-edge snapshots.
create_generated_clock -name gao_clock -source [get_ports {CLK_IN}] -divide_by 256 [get_pins {gao_clock_s*/Q}]
