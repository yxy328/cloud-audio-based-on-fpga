[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [string] $NetlistFile = 'impl/pnr/PCM5102_PAM8403.vo',
    [string] $Python = 'python'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$netlistPath = Join-Path $projectDir $NetlistFile
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
$primitives = Join-Path $GowinDir 'IDE/simlib/gw5a/prim_sim.v'
foreach ($path in @($netlistPath,$iverilog,$vvp,$primitives)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $path" }
}
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    # Diagnostic copy only: preserve every UART/parser/RAM primitive. Hold
    # other clock pins to bound simulation; production netlist is untouched.
    @'
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding='utf-8-sig')
held = 0
preserved = 0
def isolate(match):
    global held, preserved
    kind, name, body = match.group(1), match.group(2), match.group(3)
    clock_pin = r'(\.(?:CLK\w*)\()clk_d(\))'
    if name.startswith('\\u_keymap/'):
        preserved += len(re.findall(clock_pin, body))
    else:
        body, count = re.subn(clock_pin, r'\1GND\2', body)
        held += count
    return kind+' '+name+' ('+body+');'
source = re.sub(r'(?m)^(\w+)\s+(\S+)\s*\((.*?)\);', isolate, source, flags=re.S)
if not held or not preserved:
    raise SystemExit('Unsupported netlist clock/naming format; no diagnostic generated')
Path(sys.argv[2]).write_text(source, encoding='utf-8')
print(f'PNR diagnostic: UART clock pins preserved={preserved}, other clocks held={held}')
'@ | & $Python '-' $netlistPath 'sim/build/keymap_pnr_uart_only.vo'
    if ($LASTEXITCODE -ne 0) { throw 'PNR UART diagnostic preparation failed' }
    & $iverilog '-g2001' '-s' 'tb_hc05_pnr' '-o' 'sim/build/tb_hc05_pnr.vvp' 'sim/tb_hc05_pnr.v' 'sim/build/keymap_pnr_uart_only.vo' $primitives
    if ($LASTEXITCODE -ne 0) { throw 'PNR UART compile failed' }
    & $vvp '-i' 'sim/build/tb_hc05_pnr.vvp' | Tee-Object -FilePath 'sim/build/tb_hc05_pnr.log'
    if ($LASTEXITCODE -ne 0) { throw 'PNR UART simulation failed' }
} finally { Pop-Location }
