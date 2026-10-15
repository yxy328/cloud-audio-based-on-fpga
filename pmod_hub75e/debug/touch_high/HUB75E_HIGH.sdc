# Tang Primer 25K: E2 oscillator, 50MHz.
create_clock -name CLK_IN -period 20.000 [get_ports {CLK_IN}]

# Wrapper instance dut retains the same divider as the main project.
create_generated_clock -name scan_clock -source [get_ports {CLK_IN}] -divide_by 2 [get_pins {dut/scan_div*/Q}]
create_generated_clock -name gao_clock -source [get_ports {CLK_IN}] -divide_by 16 [get_pins {dut/clkn_3*/Q}]
