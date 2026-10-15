[CmdletBinding()]
param(
    [string] $IverilogDir,
    [string] $GowinSimlib,
    [ValidateSet('tb_ttp229', 'tb_ttp229_startup', 'tb_ttp229_modes', 'tb_ttp229_gpio_input', 'tb_touch_ui', 'tb_display_rom', 'tb_hub75e_scan', 'tb_gao_touch_debug', 'tb_top', 'tb_top_modes')]
    [string[]] $Tests = @('tb_ttp229', 'tb_ttp229_startup', 'tb_ttp229_modes', 'tb_ttp229_gpio_input', 'tb_touch_ui', 'tb_display_rom', 'tb_hub75e_scan', 'tb_gao_touch_debug', 'tb_top', 'tb_top_modes')
)

# Run from any directory. Outputs stay in sim/build and are not synthesis inputs.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

if ($IverilogDir) {
    $iverilog = Join-Path $IverilogDir 'iverilog.exe'
    $vvp = Join-Path $IverilogDir 'vvp.exe'
}
else {
    $iverilogCommand = Get-Command iverilog -ErrorAction SilentlyContinue
    if ($iverilogCommand) {
        $iverilog = $iverilogCommand.Source
        $vvp = Join-Path (Split-Path -Parent $iverilog) 'vvp.exe'
    }
    else {
        $iverilog = 'C:/iverilog/bin/iverilog.exe'
        $vvp = 'C:/iverilog/bin/vvp.exe'
    }
}
if (!(Test-Path -LiteralPath $iverilog -PathType Leaf) -or
    !(Test-Path -LiteralPath $vvp -PathType Leaf)) {
    throw 'Icarus Verilog was not found. Put iverilog/vvp on PATH or pass -IverilogDir <bin directory>.'
}
$iverilog = (Resolve-Path -LiteralPath $iverilog).Path
$vvp = (Resolve-Path -LiteralPath $vvp).Path

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$pythonArgs = @()
if (!$pythonCommand) {
    $pythonCommand = Get-Command py -ErrorAction SilentlyContinue
    $pythonArgs = @('-3')
}
if (!$pythonCommand) {
    throw 'Python 3 was not found. Install Python and put python or py on PATH.'
}

if (($Tests -contains 'tb_display_rom') -or ($Tests -contains 'tb_top')) {
    if (!$GowinSimlib) {
        $candidates = @()
        if ($env:GOWIN_HOME) {
            $candidates += Join-Path $env:GOWIN_HOME 'IDE/simlib/gw5a/prim_sim.v'
            $candidates += Join-Path $env:GOWIN_HOME 'simlib/gw5a/prim_sim.v'
        }
        # Local installation fallback; an explicit argument or GOWIN_HOME wins.
        $candidates += 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/simlib/gw5a/prim_sim.v'
        $GowinSimlib = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if (!$GowinSimlib -or !(Test-Path -LiteralPath $GowinSimlib -PathType Leaf)) {
        throw 'Gowin gw5a primitive library was not found. Set GOWIN_HOME or pass -GowinSimlib <gw5a/prim_sim.v>.'
    }
    $GowinSimlib = (Resolve-Path -LiteralPath $GowinSimlib).Path
}

$sources = @{
    tb_ttp229 = @('src/ttp229_ctrl.v')
    tb_ttp229_startup = @('src/ttp229_ctrl.v')
    tb_ttp229_modes = @('src/ttp229_ctrl.v', 'src/ttp229_mode_select.v')
    tb_ttp229_gpio_input = @('src/ttp229_gpio_input.v')
    tb_touch_ui = @('src/touch_ui.v')
    tb_display_rom = @('src/display_rom.v', 'src/gowin_prom/gowin_prom.v', $GowinSimlib)
    tb_hub75e_scan = @('src/top.v.v')
    tb_gao_touch_debug = @('src/gao_touch_debug.v')
    tb_top = @('src/top.v.v', 'src/ttp229_ctrl.v', 'src/ttp229_mode_select.v', 'src/ttp229_gpio_input.v', 'src/touch_ui.v',
               'src/display_rom.v', 'src/gowin_prom/gowin_prom.v', 'src/gao_touch_debug.v', $GowinSimlib)
}
$sources['tb_top_modes'] = @('src/top.v.v', 'src/ttp229_ctrl.v', 'src/ttp229_mode_select.v', 'src/ttp229_gpio_input.v', 'src/touch_ui.v', 'src/gao_touch_debug.v')

Push-Location -LiteralPath $projectDir
try {
    & $pythonCommand.Source @pythonArgs 'tools/generate_display_rom.py' '--check'
    if ($LASTEXITCODE -ne 0) {
        throw "ROM generation check failed (exit $LASTEXITCODE). Run tools/generate_display_rom.py."
    }
    # Fail before compiling if a requested source is missing.
    foreach ($test in $Tests) {
        foreach ($file in (@("sim/$test.v") + $sources[$test])) {
            if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Missing source for ${test}: $file"
            }
        }
    }
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    foreach ($test in $Tests) {
        Write-Host "Running $test"
        $output = "sim/build/$test.vvp"
        $compileArgs = @('-g2012', '-s', $test, '-o', $output, "sim/$test.v") + $sources[$test]
        & $iverilog @compileArgs
        if ($LASTEXITCODE -ne 0) {
            throw "$test compilation failed (exit $LASTEXITCODE)."
        }
        & $vvp $output
        if ($LASTEXITCODE -ne 0) {
            throw "$test simulation failed (exit $LASTEXITCODE)."
        }
    }
    Write-Host "PASS: all $($Tests.Count) requested simulations completed."
}
finally {
    Pop-Location
}
