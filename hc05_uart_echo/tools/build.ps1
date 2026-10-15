param([string]$GowinBin = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin')
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $GowinBin 'gw_sh.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Missing compiler: $compiler; pass -GowinBin <IDE bin directory>."
}
& $compiler (Join-Path $PSScriptRoot 'build.tcl')
if ($LASTEXITCODE -ne 0) { throw 'Gowin build failed.' }
