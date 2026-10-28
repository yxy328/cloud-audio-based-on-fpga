param([Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label,[ValidateRange(0,4)][int]$PlaceOption=2,[ValidateRange(0,2)][int]$RouteOption=0,[ValidateRange(1,100)][int]$MaxFan=23)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$snapshot=Join-Path $projectDir "sim/build/unified/$Label"
$target=Join-Path $snapshot 'pcm5102_pam8403'
foreach($entry in (Get-Content -LiteralPath "$snapshot/sources.json" -Raw | ConvertFrom-Json)){
    $path=Join-Path $snapshot $entry.Path
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256){throw "Frozen input changed: $path"}
}
if(!(Test-Path -LiteralPath "$target/impl/gwsynthesis/PCM5102_UNIFIED.vg")){throw 'Synthesis netlist is missing'}
$tcl=[System.IO.File]::ReadAllText("$target/tools/build_unified.tcl")
if(!$tcl.Contains('run syn')){throw 'Expected a completed synthesis-only snapshot'}
$tcl=$tcl.Replace('run syn','run pnr').Replace('Synthesis complete: [file join $project_dir impl gwsynthesis PCM5102_UNIFIED_syn.rpt.html]','Unified bitstream: [file join $project_dir impl pnr PCM5102_UNIFIED.fs]')
$tcl=$tcl.Replace('run pnr',"set_option -place_option $PlaceOption -route_option $RouteOption -route_maxfan $MaxFan`n    run pnr")
$script=Join-Path "$target/tools" 'resume_pnr.tcl'
[System.IO.File]::WriteAllText($script,$tcl,[System.Text.UTF8Encoding]::new($false))
$routeStartedUtc=[DateTime]::UtcNow
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' $script 2>&1 | Tee-Object -FilePath "$snapshot/pnr.log"
if($LASTEXITCODE -ne 0){throw "Unified PNR failed: $snapshot/pnr.log"}
if(!(Test-Path -LiteralPath "$target/impl/pnr/PCM5102_UNIFIED.fs")){throw 'PNR did not produce a bitstream'}
$routeText=[IO.File]::ReadAllText("$snapshot/pnr.log")
if(!$routeText.Contains('Placement and routing completed') -or !$routeText.Contains('Bitstream generation completed') -or $routeText -match '(?m)^ERROR\b'){throw 'PNR log does not confirm a completed, error-free bitstream'}
if((Get-Item -LiteralPath "$target/impl/pnr/PCM5102_UNIFIED.fs").LastWriteTimeUtc -lt $routeStartedUtc.AddSeconds(-1)){throw 'PNR left a stale bitstream from an earlier run'}
& python "$PSScriptRoot/check_rhythm_font_netlist.py" --netlist "$target/impl/pnr/PCM5102_UNIFIED.vo" --font "$target/src/rhythm_font.hex"
if($LASTEXITCODE -ne 0){throw 'Routed score font is missing or corrupt'}
