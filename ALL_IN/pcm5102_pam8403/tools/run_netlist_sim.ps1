[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
$primitives = Join-Path $GowinDir 'IDE/simlib/gw5a/prim_sim.v'
Push-Location -LiteralPath $projectDir
try {
    foreach ($file in @($iverilog, $vvp, $primitives, 'impl/pnr/PCM5102_AUDIT.vo')) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Missing $file. Generate the netlist with tools/build_audit.tcl first."
        }
    }
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    # Reuse the independent pin decoder. A fixed external POR count avoids
    # referencing an internal RTL net that does not survive synthesis.
    $bench = Get-Content -LiteralPath 'sim/tb_top.v' -Raw
    $bench = $bench.Replace('tb_top', 'tb_netlist')
    $bench = $bench.Replace('dut.resetn', '(master_edges > 63)')
    $bench = $bench.Replace('$dumpvars(0, tb_netlist);', '$dumpvars(1, tb_netlist);')
    Set-Content -LiteralPath 'sim/build/tb_netlist.v' -Value $bench -Encoding utf8
    & $iverilog '-g2001' '-s' 'tb_netlist' '-o' 'sim/build/tb_netlist.vvp' 'sim/build/tb_netlist.v' 'impl/pnr/PCM5102_AUDIT.vo' $primitives
    if ($LASTEXITCODE -ne 0) { throw 'Primitive netlist compile failed.' }
    & $vvp 'sim/build/tb_netlist.vvp'
    if ($LASTEXITCODE -ne 0) { throw 'Primitive netlist simulation failed.' }
    Write-Host 'PASS: post-route primitive functional simulation (without SDF annotation).'
}
finally { Pop-Location }
