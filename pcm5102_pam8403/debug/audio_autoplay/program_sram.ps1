[CmdletBinding()]
param(
    [string] $ProgrammerDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin',
    [int] $CableLocation = 385
)
$ErrorActionPreference = 'Stop'
$cli = Join-Path $ProgrammerDir 'programmer_cli.exe'
$bitstream = Join-Path $PSScriptRoot 'impl/pnr/ao_0.fs'
foreach ($path in @($cli, $bitstream)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $path" }
}
# Operation 2 programs SRAM only. It does not burn external Flash.
$output = & $cli --device GW5A-25A --cable-index 4 --location $CableLocation --frequency 15MHz --operation_index 2 --fsFile $bitstream 2>&1
$programExit = $LASTEXITCODE
$output | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'programmer_sram.log') -Encoding utf8
$logText = $output -join "`n"
if ($programExit -ne 0 -or $logText -match '(?im)\b(error|failed|failure)\b' -or $logText -notmatch 'Finished\.') {
    throw 'SRAM download did not complete; inspect programmer_sram.log.'
}
Write-Host 'SRAM download completed: automatic 440 Hz tone, digital gain 1/16.'
