[CmdletBinding()]
param([string] $IverilogDir = 'C:/iverilog/bin')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
foreach ($tool in @($iverilog, $vvp)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing simulator: $tool; pass -IverilogDir <bin directory>."
    }
}
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    foreach ($test in @('tb_ttp229_gpio', 'tb_ttp229_gpio_modes')) {
        $output = "sim/build/$test.vvp"
        & $iverilog '-g2012' '-s' $test '-o' $output "sim/$test.v" 'src/ttp229_gpio_top.v' '../pmod_hub75e/src/ttp229_ctrl.v' '../pmod_hub75e/src/ttp229_mode_select.v'
        if ($LASTEXITCODE -ne 0) { throw "$test compile failed." }
        & $vvp $output
        if ($LASTEXITCODE -ne 0) { throw "$test simulation failed." }
    }
    Write-Host 'PASS: GPIO eight-key and S2 mode-switch simulations completed.'
}
finally { Pop-Location }
