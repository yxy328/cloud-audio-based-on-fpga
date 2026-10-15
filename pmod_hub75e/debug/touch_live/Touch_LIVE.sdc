# Free-running GAO clock directly from the E2 50 MHz oscillator.
create_clock -name CLK_IN -period 20.000 [get_ports {CLK_IN}]
