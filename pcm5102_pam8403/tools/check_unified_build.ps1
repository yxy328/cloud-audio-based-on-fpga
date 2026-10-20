param([Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label,[string[]]$OnehotModules=@(),[string[]]$DefaultEncodingModules=@(),[int]$SynthesisMHz=50,[switch]$SynthesisOnly)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$snapshot=Join-Path $projectDir "sim/build/unified/$Label"
if(Test-Path -LiteralPath $snapshot){throw "Snapshot already exists: $snapshot"}
$target=Join-Path $snapshot 'pcm5102_pam8403'
New-Item -ItemType Directory -Path "$target/tools","$target/impl","$snapshot/pmod_hub75e" -Force | Out-Null
Copy-Item -LiteralPath "$projectDir/src" -Destination $target -Recurse
Copy-Item -LiteralPath "$projectDir/../pmod_hub75e/src" -Destination "$snapshot/pmod_hub75e" -Recurse
Copy-Item -LiteralPath "$projectDir/PCM5102_UNIFIED.gprj" -Destination $target
Copy-Item -LiteralPath "$PSScriptRoot/build_unified.tcl" -Destination "$target/tools"
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
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' "$target/tools/build_unified.tcl" 2>&1 | Tee-Object -FilePath "$snapshot/build.log"
if($LASTEXITCODE -ne 0){throw "Unified build failed: $snapshot/build.log"}
