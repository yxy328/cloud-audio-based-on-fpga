param([string]$IverilogDir='C:/iverilog/bin',[switch]$RoutedScan)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    & python tools/generate_rhythm_tables.py --check
    if($LASTEXITCODE -ne 0){throw 'Rhythm ROMs differ'}
    & python tools/generate_hc05_decoder.py --check
    if($LASTEXITCODE -ne 0){throw 'HC05 decoder differs'}
    & ./tools/run_sim.ps1 -Quick -IverilogDir $IverilogDir -Tests @('tb_rhythm_game','tb_rhythm_types','tb_rhythm_tails','tb_rhythm_panel','tb_rhythm_raster','tb_rhythm_protocol','tb_rhythm_top','tb_rhythm_types_top','tb_control12_dense','tb_hc05_visual','tb_control12_live_equivalence','tb_sensor_staging_equivalence','tb_control12_take','tb_fx_take_atomic_528')
    & ./android_app/test-core.ps1
    if($LASTEXITCODE -ne 0){throw 'App core tests failed'}
    if($RoutedScan){
        & "$IverilogDir/iverilog.exe" -g2001 -s tb_rhythm_netlist -o sim/build/rhythm_routed_scan.vvp sim/tb_rhythm_netlist.v impl/pnr/PCM5102_UNIFIED.vo E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/simlib/gw5a/prim_sim.v
        if($LASTEXITCODE -ne 0){throw 'Routed scan compile failed'}
        & "$IverilogDir/vvp.exe" -i sim/build/rhythm_routed_scan.vvp +scan_only | Tee-Object -FilePath sim/build/rhythm_routed_scan.log
        if($LASTEXITCODE -ne 0){throw 'Routed scan test failed'}
    }
} finally { Pop-Location }
