[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [string] $NetlistFile = 'impl/pnr/PCM5102_PAM8403.vo'
)
$ErrorActionPreference = 'Stop'
# Build the current project with tools/build.tcl first. To inspect the audit
# build, pass -NetlistFile impl/pnr/PCM5102_AUDIT.vo after build_audit.tcl.
& (Join-Path $PSScriptRoot 'run_sim.ps1') -IverilogDir $IverilogDir -GowinDir $GowinDir -Netlist -NetlistFile $NetlistFile
