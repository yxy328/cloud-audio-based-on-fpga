param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$SourceLabel,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label,
    [ValidateRange(0,4)][int]$PlaceOption=0,[ValidateRange(0,2)][int]$RouteOption=0,[ValidateRange(1,100)][int]$MaxFan=23)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$source=Join-Path $projectDir "sim/build/unified/$SourceLabel"
$target=Join-Path $projectDir "sim/build/unified/$Label"
if(Test-Path -LiteralPath $target){throw "Variant already exists: $target"}
New-Item -ItemType Directory -Path "$target/pcm5102_pam8403/impl","$target/pcm5102_pam8403/tools","$target/pmod_hub75e" -Force | Out-Null
Copy-Item -LiteralPath "$source/pcm5102_pam8403/src" -Destination "$target/pcm5102_pam8403" -Recurse
Copy-Item -LiteralPath "$source/pmod_hub75e/src" -Destination "$target/pmod_hub75e" -Recurse
Copy-Item -LiteralPath "$source/pcm5102_pam8403/impl/gwsynthesis" -Destination "$target/pcm5102_pam8403/impl" -Recurse
Copy-Item -LiteralPath "$source/pcm5102_pam8403/impl/PCM5102_UNIFIED_process_config.json" -Destination "$target/pcm5102_pam8403/impl"
Copy-Item -LiteralPath "$source/pcm5102_pam8403/PCM5102_UNIFIED.gprj" -Destination "$target/pcm5102_pam8403"
Copy-Item -LiteralPath "$source/pcm5102_pam8403/tools/build_unified.tcl" -Destination "$target/pcm5102_pam8403/tools"
Copy-Item -LiteralPath "$source/sources.json" -Destination $target
& "$PSScriptRoot/resume_unified_pnr.ps1" -Label $Label -PlaceOption $PlaceOption -RouteOption $RouteOption -MaxFan $MaxFan
