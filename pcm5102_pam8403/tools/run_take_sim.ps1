[CmdletBinding()]
param([string] $IverilogDir = 'C:/iverilog/bin')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    & (Join-Path $IverilogDir 'iverilog.exe') -g2001 -Wall -s tb_performance_take -o sim/build/tb_performance_take.vvp sim/tb_performance_take.v src/performance_take.v
    if ($LASTEXITCODE -ne 0) { throw 'Event timeline compilation failed' }
    & (Join-Path $IverilogDir 'vvp.exe') sim/build/tb_performance_take.vvp | Tee-Object -FilePath sim/build/tb_performance_take.log
    if ($LASTEXITCODE -ne 0) { throw 'Event timeline simulation failed' }
} finally { Pop-Location }
