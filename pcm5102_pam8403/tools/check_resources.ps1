[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string] $Label,
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string] $ReferenceLabel,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string] $OverlayLabel,
    [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
    [string[]] $OverlaySource,
    [switch] $SynthesisOnly
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$repoDir = Split-Path -Parent $projectDir
$sourceProject = $projectDir
$sourceShared = Join-Path $repoDir 'pmod_hub75e'
if ($ReferenceLabel) {
    $reference = Join-Path $projectDir "sim/build/resource_optimization/$ReferenceLabel"
    $sourceProject = Join-Path $reference 'pcm5102_pam8403'
    $sourceShared = Join-Path $reference 'pmod_hub75e'
    if (!(Test-Path -LiteralPath "$reference/sources.json")) { throw "Missing reference snapshot: $reference" }
} elseif ($OverlaySource) { throw '-OverlaySource requires -ReferenceLabel' }
$overlayProject = $projectDir
if ($OverlayLabel) {
    if (!$ReferenceLabel -or !$OverlaySource) { throw '-OverlayLabel requires -ReferenceLabel and -OverlaySource' }
    $overlayRoot = Join-Path $projectDir "sim/build/resource_optimization/$OverlayLabel"
    if (!(Test-Path -LiteralPath "$overlayRoot/sources.json")) { throw "Missing overlay snapshot: $overlayRoot" }
    $overlayProject = Join-Path $overlayRoot 'pcm5102_pam8403'
}
$snapshot = Join-Path $projectDir "sim/build/resource_optimization/$Label"
if (Test-Path -LiteralPath $snapshot) { throw "Snapshot already exists: $snapshot. Use a new label." }
$snapshotProject = Join-Path $snapshot 'pcm5102_pam8403'
New-Item -ItemType Directory -Path "$snapshotProject/tools", "$snapshotProject/impl", "$snapshot/pmod_hub75e" -Force | Out-Null
Copy-Item -LiteralPath "$sourceProject/src" -Destination $snapshotProject -Recurse
Copy-Item -LiteralPath "$sourceShared/src" -Destination "$snapshot/pmod_hub75e" -Recurse
Copy-Item -LiteralPath "$sourceProject/PCM5102_PAM8403.gprj" -Destination $snapshotProject
Copy-Item -LiteralPath "$sourceProject/impl/PCM5102_PAM8403_process_config.json" -Destination "$snapshotProject/impl"
foreach ($file in $OverlaySource) {
    Copy-Item -LiteralPath "$overlayProject/src/$file" -Destination "$snapshotProject/src/$file"
}
Copy-Item -LiteralPath "$PSScriptRoot/check_resources.tcl" -Destination "$snapshotProject/tools"
$manifest = Get-ChildItem -LiteralPath $snapshot -File -Recurse | ForEach-Object {
    [pscustomobject]@{ Path=$_.FullName.Substring($snapshot.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath "$snapshot/sources.json" -Encoding utf8
$previousSynOnly = $env:RESOURCE_SYN_ONLY
try {
    $env:RESOURCE_SYN_ONLY = if ($SynthesisOnly) { '1' } else { '0' }
    & "$GowinDir/IDE/bin/gw_sh.exe" "$snapshotProject/tools/check_resources.tcl" 2>&1 | Tee-Object -FilePath "$snapshot/build.log"
    if ($LASTEXITCODE -ne 0) { throw "Gowin resource check failed; see $snapshot/build.log" }
    Write-Output "Resource snapshot: $snapshot"
} finally {
    $env:RESOURCE_SYN_ONLY = $previousSynOnly
}
