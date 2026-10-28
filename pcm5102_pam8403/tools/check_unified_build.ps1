param([Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label,[string[]]$OnehotModules=@(),[string[]]$DefaultEncodingModules=@(),[int]$SynthesisMHz=50,[int]$PlaceOption=-1,[int]$RouteOption=-1,[int]$RouteMaxfan=-1,[string]$ParameterOverride='',[switch]$SynthesisOnly)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$snapshot=Join-Path $projectDir "sim/build/unified/$Label"
if(Test-Path -LiteralPath $snapshot){throw "Snapshot already exists: $snapshot"}
$target=Join-Path $snapshot 'pcm5102_pam8403'
New-Item -ItemType Directory -Path "$target/tools","$target/impl","$snapshot/pmod_hub75e" -Force | Out-Null
$rhythmProcess=Join-Path $projectDir 'impl/PCM5102_UNIFIED_process_config.json'
if(Test-Path -LiteralPath $rhythmProcess){
    New-Item -ItemType Directory -Path "$snapshot/build_inputs" -Force | Out-Null
    Copy-Item -LiteralPath $rhythmProcess -Destination "$snapshot/build_inputs/PCM5102_UNIFIED_process_config.json"
}
Copy-Item -LiteralPath "$projectDir/src" -Destination $target -Recurse
Copy-Item -LiteralPath "$projectDir/../pmod_hub75e/src" -Destination "$snapshot/pmod_hub75e" -Recurse
Copy-Item -LiteralPath "$projectDir/PCM5102_UNIFIED.gprj" -Destination $target
Copy-Item -LiteralPath "$PSScriptRoot/build_unified.tcl" -Destination "$target/tools"
# Same-source A/B: rewrite one top-level parameter inside the snapshot only, so
# the two builds differ by that parameter and nothing else. The rewritten file
# is hashed in sources.json and the override is recorded beside it.
if($ParameterOverride){
    $pair=$ParameterOverride -split '=',2
    if($pair.Count -ne 2 -or !$pair[0] -or $pair[1] -notmatch '^\d+$'){throw 'ParameterOverride must be Name=Number'}
    $file=Join-Path "$target/src" 'top.v'
    $source=[System.IO.File]::ReadAllText($file)
    $pattern='(parameter\s+'+[regex]::Escape($pair[0])+'\s*=\s*)(\d+)'
    if($source -notmatch $pattern){throw "Top parameter $($pair[0]) not found in src/top.v"}
    $source=[regex]::Replace($source,$pattern,('${1}'+$pair[1]))
    [System.IO.File]::WriteAllText($file,$source,[System.Text.UTF8Encoding]::new($false))
    "ParameterOverride $($pair[0])=$($pair[1]) applied to src/top.v" | Set-Content -LiteralPath "$snapshot/parameter_override.txt" -Encoding ascii
    Write-Output "Parameter override: $($pair[0])=$($pair[1])"
}
if($SynthesisOnly){
    $script=Join-Path "$target/tools" 'build_unified.tcl'
    $source=[System.IO.File]::ReadAllText($script).Replace('run all','run syn').Replace('Audio take bitstream: [file join $project_dir impl pnr PCM5102_UNIFIED.fs]','Synthesis complete: [file join $project_dir impl gwsynthesis PCM5102_UNIFIED_syn.rpt.html]')
    [System.IO.File]::WriteAllText($script,$source,[System.Text.UTF8Encoding]::new($false))
}
if($SynthesisMHz -ne 50){
    $script=Join-Path "$target/tools" 'build_unified.tcl'
    $source=[System.IO.File]::ReadAllText($script).Replace('-global_freq 50',"-global_freq $SynthesisMHz").Replace('run all',"run syn`n    set_option -global_freq 50`n    run pnr")
    [System.IO.File]::WriteAllText($script,$source,[System.Text.UTF8Encoding]::new($false))
}
if($PlaceOption -ge 0 -or $RouteOption -ge 0 -or $RouteMaxfan -ge 0){
    $script=Join-Path "$target/tools" 'build_unified.tcl'
    $source=[System.IO.File]::ReadAllText($script)
    if($PlaceOption -ge 0){$source=[regex]::Replace($source,'(-place_option )\d+',('${1}'+$PlaceOption))}
    if($RouteOption -ge 0){$source=[regex]::Replace($source,'(-route_option )\d+',('${1}'+$RouteOption))}
    if($RouteMaxfan -ge 0){$source=[regex]::Replace($source,'(-route_maxfan )\d+',('${1}'+$RouteMaxfan))}
    [System.IO.File]::WriteAllText($script,$source,[System.Text.UTF8Encoding]::new($false))
    Write-Output "PnR strategy: place=$PlaceOption route=$RouteOption maxfan=$RouteMaxfan"
}
foreach($module in $OnehotModules){
    if($module -notmatch '^[a-z0-9_]+\.v$'){throw 'Invalid module name'}
    $file=Join-Path "$target/src" $module
    $source=[System.IO.File]::ReadAllText($file)
    $source=[regex]::Replace($source,'(?m)^(\s*)reg (\[[^\r\n]+?\]\s+state(?:,return_state|,saved_kind|,stage)?;)','$1(* syn_encoding="onehot" *) reg $2')
    [System.IO.File]::WriteAllText($file,$source,[System.Text.UTF8Encoding]::new($false))
}
foreach($module in $DefaultEncodingModules){
    if($module -notmatch '^[a-z0-9_]+\.v$'){throw 'Invalid module name'}
    $file=Join-Path "$target/src" $module
    $source=[System.IO.File]::ReadAllText($file).Replace('(* syn_encoding="onehot" *) ','')
    [System.IO.File]::WriteAllText($file,$source,[System.Text.UTF8Encoding]::new($false))
}
Get-ChildItem -LiteralPath $snapshot -File -Recurse | ForEach-Object {
    [pscustomobject]@{Path=$_.FullName.Substring($snapshot.Length+1);SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
} | ConvertTo-Json | Set-Content -LiteralPath "$snapshot/sources.json" -Encoding utf8
$buildStartedUtc=[DateTime]::UtcNow
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' "$target/tools/build_unified.tcl" 2>&1 | Tee-Object -FilePath "$snapshot/build.log"
if($LASTEXITCODE -ne 0){throw "Unified build failed: $snapshot/build.log"}
if(!$SynthesisOnly){
    $routeText=[IO.File]::ReadAllText("$snapshot/build.log")
    if(!$routeText.Contains('Placement and routing completed') -or !$routeText.Contains('Bitstream generation completed') -or $routeText -match '(?m)^ERROR\b'){throw 'Build log does not confirm a completed, error-free bitstream'}
    if(!(Test-Path -LiteralPath "$target/impl/pnr/PCM5102_UNIFIED.fs")){throw 'Build did not produce a bitstream'}
    if((Get-Item -LiteralPath "$target/impl/pnr/PCM5102_UNIFIED.fs").LastWriteTimeUtc -lt $buildStartedUtc.AddSeconds(-1)){throw 'Build left a stale bitstream'}
    & python "$PSScriptRoot/check_rhythm_font_netlist.py" --netlist "$target/impl/pnr/PCM5102_UNIFIED.vo" --font "$target/src/rhythm_font.hex"
    if($LASTEXITCODE -ne 0){throw 'Routed score font is missing or corrupt'}
}
