# Tang Primer 25K: E2 oscillator, 50MHz.
create_clock -name CLK_IN -period 20.000 [get_ports {CLK_IN}]

# Panel divider retains its reset phase: scan_div, 50MHz / 2 = 25MHz.
create_generated_clock -name scan_clock -source [get_ports {CLK_IN}] -divide_by 2 [get_pins {scan_div*/Q}]

# GAO sample clock: clkn[3], period 320ns. Keep the two divider clocks separate.
create_generated_clock -name gao_clock -source [get_ports {CLK_IN}] -divide_by 16 [get_pins {clkn_3*/Q}]
