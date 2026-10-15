[CmdletBinding()]
param(
    [string] $GowinBin = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $GowinBin 'gw_sh.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Missing compiler: $compiler; pass -GowinBin <IDE bin directory>."
}
Push-Location -LiteralPath $projectDir
try {
    & $compiler 'tools/build.tcl'
    if ($LASTEXITCODE -ne 0) { throw 'Gowin build failed.' }
    $bitstream = Join-Path $projectDir 'impl/pnr/TTP229_SERIAL16.fs'
    if (!(Test-Path -LiteralPath $bitstream -PathType Leaf)) {
        throw "Missing output: $bitstream"
    }
    Write-Host "Built: $bitstream"
    Get-FileHash -LiteralPath $bitstream -Algorithm SHA256
}
finally { Pop-Location }
