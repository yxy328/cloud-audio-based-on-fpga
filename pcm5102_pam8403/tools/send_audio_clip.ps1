[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $Port,
    [int] $Baud = 9600,
    [string] $Commands = (Join-Path $PSScriptRoot '../audio_clips/settlement_4s.txt'),
    [switch] $SkipPlay
)
$ErrorActionPreference = 'Stop'
$lines = @(Get-Content -LiteralPath $Commands | Where-Object { $_.Length -gt 0 })
if ($lines.Count -lt 3 -or $lines[0] -notmatch '^PCM_BEGIN,\d+,\d+$' -or $lines[-2] -ne 'PCM_END' -or $lines[-1] -ne 'PCM_PLAY') {
    throw 'Expected PCM_BEGIN, PCM_DATA lines, PCM_END, PCM_PLAY in command file'
}
foreach ($line in $lines) {
    if ($line.Length -gt 64 -or $line -notmatch '^PCM_(BEGIN,\d+,\d+|DATA,\d+,[0-9A-Fa-f]{2,32}|END|PLAY)$') {
        throw "Invalid command file line: $line"
    }
}
$serial = [System.IO.Ports.SerialPort]::new($Port,$Baud,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 3000
$serial.WriteTimeout = 3000
$serial.Encoding = [System.Text.Encoding]::ASCII
function Send-Command([string] $Command, [string] $Expected = 'OK') {
    # Only complete DATA blocks are retried; their writes are idempotent.
    $attempts = if ($Command.StartsWith('PCM_DATA,')) { 3 } else { 1 }
    for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
        $serial.WriteLine($Command)
        try {
            do { $reply = $serial.ReadLine().TrimEnd("`r") }
            while ($reply.Length -eq 0 -or $reply.StartsWith('EVT,') -or $reply.StartsWith('MAP,') -or $reply.StartsWith('REC_END,'))
        } catch [System.TimeoutException] {
            if ($attempt -eq $attempts-1) { throw "Timed out waiting for $Command; reconnect and restart the upload" }
            continue
        }
        if ($reply -ne $Expected) { throw "$Command returned $reply; upload stopped" }
        return
    }
}
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    # EOL terminates any old partial line; PING establishes command framing.
    $serial.WriteLine('')
    $serial.WriteLine('PING')
    do { $sync = $serial.ReadLine().TrimEnd("`r") } while ($sync -ne 'PONG')
    Send-Command 'STOP'
    Send-Command 'REC_STOP'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($SkipPlay -and $lines[$i] -eq 'PCM_PLAY') { continue }
        Send-Command $lines[$i]
        if ($i % 100 -eq 0 -or $i -eq $lines.Count-1) {
            Write-Progress -Activity 'Downloading PCM to FPGA RAM' -Status "$i / $($lines.Count) lines" -PercentComplete (100*$i/$lines.Count)
        }
    }
    Write-Progress -Activity 'Downloading PCM to FPGA RAM' -Completed
    Write-Host "Download verified by FPGA; elapsed $([math]::Round($watch.Elapsed.TotalSeconds,1)) seconds."
    if (!$SkipPlay) { Write-Host 'PCM_PLAY accepted. Disconnecting Bluetooth does not erase RAM; S1 plays/stops and S2 restarts.' }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
