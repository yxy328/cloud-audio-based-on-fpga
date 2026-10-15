param([switch]$Vcd)
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
$image = Join-Path $buildDir 'ttp229_serial16.vvp'
$sources = @(
    (Join-Path $projectRoot 'sim/tb_ttp229_serial16.sv'),
    (Join-Path $projectRoot 'src/ttp229_serial16.v'),
    (Join-Path $projectRoot 'src/ttp229_uart_report.v'),
    (Join-Path $projectRoot 'src/ttp229_serial16_top.v')
)
& $iverilog -g2012 -Wall -s tb_ttp229_serial16 -o $image @sources
if ($LASTEXITCODE -ne 0) { throw 'Icarus compilation failed.' }
Push-Location $buildDir
try {
    $log = Join-Path $buildDir 'simulation.log'
    if ($Vcd) { & $vvp $image '+vcd' | Tee-Object -FilePath $log }
    else { & $vvp $image | Tee-Object -FilePath $log }
    if ($LASTEXITCODE -ne 0) { throw 'Self-checking simulation failed.' }
} finally {
    Pop-Location
}
