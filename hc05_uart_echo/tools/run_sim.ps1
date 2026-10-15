$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildDir = Join-Path $projectRoot 'sim/build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$iverilog = 'C:/iverilog/bin/iverilog.exe'
$vvp = 'C:/iverilog/bin/vvp.exe'
if (-not (Test-Path -LiteralPath $iverilog)) {
    $iverilog = (Get-Command iverilog -ErrorAction Stop).Source
    $vvp = (Get-Command vvp -ErrorAction Stop).Source
}
$image = Join-Path $buildDir 'uart_echo.vvp'
& $iverilog -g2012 -Wall -s tb_uart_echo -o $image (Join-Path $projectRoot 'sim/tb_uart_echo.sv') (Join-Path $projectRoot 'src/uart_echo.v') (Join-Path $projectRoot 'src/hc05_uart_echo_top.v')
if ($LASTEXITCODE -ne 0) { throw 'Icarus compilation failed.' }
& $vvp $image | Tee-Object -FilePath (Join-Path $buildDir 'simulation.log')
if ($LASTEXITCODE -ne 0) { throw 'Simulation failed.' }
