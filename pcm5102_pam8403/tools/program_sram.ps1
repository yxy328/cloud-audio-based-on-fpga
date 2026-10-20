[CmdletBinding()]
param(
    [string] $ProgrammerDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin',
    [int] $CableLocation = 385
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $ProgrammerDir 'programmer_cli.exe'
$bitstream = Join-Path $projectDir 'impl/pnr/PCM5102_UNIFIED.fs'
foreach ($path in @($cli,$bitstream)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $path" }
}
$header = (Get-Content -LiteralPath $bitstream -TotalCount 40) -join "`n"
$expectedCode = [regex]::Match($header, '(?m)^//UserCode:\s*(0x[0-9a-fA-F]+)')
if (!$expectedCode.Success) { throw 'Bitstream has no UserCode header' }
$output = & $cli --device GW5A-25A --cable-index 4 --location $CableLocation --frequency 15MHz --operation_index 2 --fsFile $bitstream 2>&1
$programExit = $LASTEXITCODE
$output | Set-Content -LiteralPath (Join-Path $projectDir 'programmer_sram.log') -Encoding utf8
$logText = $output -join "`n"
if ($programExit -ne 0 -or $logText -match '(?im)\b(error|failed|failure)\b' -or $logText -notmatch 'Finished\.') {
    throw 'SRAM download failed; inspect programmer_sram.log'
}
$readback = & $cli --device GW5A-25A --cable-index 4 --location $CableLocation --frequency 15MHz --operation_index 0 2>&1
$readExit = $LASTEXITCODE
$readback | Set-Content -LiteralPath (Join-Path $projectDir 'programmer_verify.log') -Encoding utf8
$readText = $readback -join "`n"
$actualCode = [regex]::Match($readText, 'User Code is:\s*(0x[0-9a-fA-F]+)')
if ($readExit -ne 0 -or !$actualCode.Success -or $readText -match '(?im)\b(error|failed|failure)\b' -or $readText -notmatch 'Finished\.') {
    throw 'Cannot read back device code; inspect programmer_verify.log'
}
if ([Convert]::ToUInt32($actualCode.Groups[1].Value.Substring(2),16) -ne [Convert]::ToUInt32($expectedCode.Groups[1].Value.Substring(2),16)) {
    throw "Device UserCode $($actualCode.Groups[1].Value) differs from bitstream $($expectedCode.Groups[1].Value)"
}
Write-Host "PCM5102_UNIFIED SRAM downloaded and UserCode checked: $($actualCode.Groups[1].Value). See android_app/UNIFIED_RECORDING.md for playing and recording."
