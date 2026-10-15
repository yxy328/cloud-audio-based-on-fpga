[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [string[]] $Tests,
    [switch] $Netlist
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
foreach ($tool in @($iverilog, $vvp)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing $tool" }
}
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    if ($Netlist) {
        $rtl = @('impl/pnr/DDS_STEP1.vo', (Join-Path $GowinDir 'IDE/simlib/gw5a/prim_sim.v'))
        $defaultTests = @('tb_top')
    } else {
        $rtl = @('src/clk_div.v','src/i2s_tx.v','src/button_filter.v','src/pitch_control.v','src/sine_rom.v','src/dds_voice.v','src/top.v')
        $defaultTests = @('tb_dds_voice', 'tb_button_filter', 'tb_top')
    }
    $selectedTests = if ($Tests) { $Tests } else { $defaultTests }
    foreach ($test in $selectedTests) {
        $suffix = if ($Netlist) { '_netlist' } else { '' }
        $output = "sim/build/$test$suffix.vvp"
        & $iverilog '-g2001' '-Wall' '-s' $test '-o' $output "sim/$test.v" @rtl
        if ($LASTEXITCODE -ne 0) { throw "$test compile failed" }
        & $vvp '-i' $output | Tee-Object -FilePath "sim/build/$test$suffix.log"
        if ($LASTEXITCODE -ne 0) { throw "$test simulation failed" }
    }
} finally { Pop-Location }
