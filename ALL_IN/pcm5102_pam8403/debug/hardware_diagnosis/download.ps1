[CmdletBinding()]
param(
    [ValidateSet('01_continuous_440hz.fs', '02_current_top_gao.fs')]
    [string] $Bitstream = '01_continuous_440hz.fs',
    [string] $ProgrammerDir = 'D:/G/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin',
    [ValidateRange(0, 2147483647)]
    [int] $CableLocation = 0,
    [ValidateSet('2.5MHz', '0.1MHz', '15MHz')]
    [string] $Frequency = '2.5MHz'
)
$ErrorActionPreference = 'Stop'
$gowinCli = Join-Path $ProgrammerDir 'programmer_cli.exe'
$diagBitstream = Join-Path $PSScriptRoot $Bitstream
foreach ($requiredFile in @($gowinCli, $diagBitstream)) {
    if (!(Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Missing file: $requiredFile"
    }
}
$fsHeader = (Get-Content -LiteralPath $diagBitstream -TotalCount 40) -join "`n"
$expectedUserCode = [regex]::Match($fsHeader, '(?im)^//UserCode:\s*(0x[0-9a-f]+)')
if (!$expectedUserCode.Success) { throw 'Bitstream has no UserCode header.' }

function Invoke-DiagnosticProgrammer {
    param([string[]] $GowinArguments, [string] $LogName)
    $nativeOutput = @(& $gowinCli @GowinArguments 2>&1)
    $nativeExit = $LASTEXITCODE
    $nativeText = ($nativeOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $nativeText | Set-Content -LiteralPath (Join-Path $PSScriptRoot $LogName) -Encoding utf8
    if ($nativeText) { Write-Host $nativeText }
    [pscustomobject]@{ ExitCode = $nativeExit; Text = $nativeText }
}

# The USB location changes with ports/reconnection. Only choose channel A/0;
# never silently switch to the other enumerated FTDI channel.
$cableInventory = Invoke-DiagnosticProgrammer -GowinArguments @('--scan-cables', 'F') -LogName 'download_cables.log'
if ($cableInventory.ExitCode -ne 0) {
    throw 'No usable download cable. Check USB data cable, power and driver; see download_cables.log.'
}
$cableIndexes = @{
    'Gowin USB Cable(GWU2X)' = 0
    'Gowin USB Cable(FT2CH)' = 1
    'Digilent USB Device' = 3
    'USB Debugger A' = 4
    'Gowin USB Cable(WINUSB)' = 5
}
$cableCandidates = @(
    foreach ($cableMatch in [regex]::Matches($cableInventory.Text, '(?m)^\s*Cable found:\s*(?<name>.+?)/(?<channel>\d+)/(?<location>\d+)/')) {
        $cableName = $cableMatch.Groups['name'].Value.Trim()
        $channelNumber = [int] $cableMatch.Groups['channel'].Value
        if ($channelNumber -eq 0 -and $cableIndexes.ContainsKey($cableName)) {
            [pscustomobject]@{
                Name = $cableName
                Index = $cableIndexes[$cableName]
                Location = [int] $cableMatch.Groups['location'].Value
            }
        }
    }
)
if ($CableLocation -ne 0) {
    $cableCandidates = @($cableCandidates | Where-Object { $_.Location -eq $CableLocation })
}
if ($cableCandidates.Count -eq 0) {
    throw 'No supported channel-A download cable at the requested location; see download_cables.log.'
}
if ($cableCandidates.Count -gt 1) {
    $candidateLocations = ($cableCandidates.Location -join ', ')
    throw "Multiple download cables: $candidateLocations. Pass -CableLocation with the target board's location."
}
$selectedCable = $cableCandidates[0]
$connectionArguments = @('--cable-index', [string] $selectedCable.Index,
    '--location', [string] $selectedCable.Location, '--frequency', $Frequency)
Write-Host "Using $($selectedCable.Name), channel A, location $($selectedCable.Location)."

# Scan the physical JTAG chain before supplying an expected device name. A
# printed Target Device header alone is not evidence that an FPGA was found.
$deviceScan = Invoke-DiagnosticProgrammer -GowinArguments ($connectionArguments + @('--scan')) -LogName 'download_scan.log'
if ($deviceScan.ExitCode -ne 0 -or $deviceScan.Text -match '(?i)\b(error|failed|failure)\b' -or
    $deviceScan.Text -notmatch '(?i)GW5A|0x0001281B') {
    throw 'Target GW5A FPGA was not found. Check FPGA power, core-board connection and JTAG; see download_scan.log.'
}

# Operation 2 writes volatile SRAM, not Flash.
Write-Host "Programming $Bitstream; expected UserCode=$($expectedUserCode.Groups[1].Value)."
$programResult = Invoke-DiagnosticProgrammer -GowinArguments (
    $connectionArguments + @('--device', 'GW5A-25A', '--operation_index', '2', '--fsFile', $diagBitstream)
) -LogName 'download_program.log'
if ($programResult.ExitCode -ne 0 -or $programResult.Text -match '(?i)\b(error|failed|failure)\b' -or
    $programResult.Text -notmatch 'Finished\.') {
    throw 'SRAM program did not finish successfully; see download_program.log. Do not treat silence as an audio-test result yet.'
}

$readResult = Invoke-DiagnosticProgrammer -GowinArguments (
    $connectionArguments + @('--device', 'GW5A-25A', '--operation_index', '0')
) -LogName 'download_verify.log'
$actualUserCode = [regex]::Match($readResult.Text, '(?i)User\s*Code\s*(?:is\s*)?:\s*(0x[0-9a-f]+)')
if ($readResult.ExitCode -ne 0 -or $readResult.Text -match '(?i)\b(error|failed|failure)\b' -or
    $readResult.Text -notmatch 'Finished\.' -or !$actualUserCode.Success) {
    throw 'Cannot read back the loaded UserCode; see download_verify.log.'
}
$expectedCodeValue = [Convert]::ToUInt32($expectedUserCode.Groups[1].Value.Substring(2), 16)
$actualCodeValue = [Convert]::ToUInt32($actualUserCode.Groups[1].Value.Substring(2), 16)
if ($expectedCodeValue -ne $actualCodeValue) {
    throw "UserCode mismatch: expected $($expectedUserCode.Groups[1].Value), read $($actualUserCode.Groups[1].Value)."
}

Write-Host "SUCCESS: SRAM programmed; UserCode verified: $($actualUserCode.Groups[1].Value)."
if ($Bitstream -eq '01_continuous_440hz.fs') {
    Write-Host 'Keep power connected. A continuous 440Hz tone should play without pressing any key.'
} else {
    Write-Host 'Keep power connected. Open 02_current_top_gao.gao to capture the current integrated top.'
}
