[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [string] $NetlistFile = 'impl/pnr/PCM5102_PAM8403.vo'
)
$ErrorActionPreference = 'Stop'
# Historical normal-top netlist check; these benches instantiate top.
# The unified build uses top_unified. Supply a matching normal-top netlist
# explicitly; the former audit builder is in archive/legacy_projects/tools/.
& (Join-Path $PSScriptRoot 'run_sim.ps1') -IverilogDir $IverilogDir -GowinDir $GowinDir -Netlist -NetlistFile $NetlistFile
