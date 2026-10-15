[CmdletBinding()]
param([string] $GowinBin = 'D:/G/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $GowinBin 'gw_sh.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Gowin compiler not found: $compiler; pass -GowinBin <IDE/bin directory>."
}
Push-Location -LiteralPath $projectDir
try {
    & $compiler (Join-Path $PSScriptRoot 'build.tcl')
    if ($LASTEXITCODE -ne 0) { throw "Gowin build failed ($LASTEXITCODE); inspect impl logs." }
}
finally { Pop-Location }
