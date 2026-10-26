param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
# Only the three generated files whose previous contents have been backed up.
foreach ($name in @('PCM5102_UNIFIED.fs', 'PCM5102_UNIFIED.bin', 'PCM5102_UNIFIED.binx')) {
    $outputPath = Join-Path $ProjectRoot ('impl/pnr/' + $name)
    $outputFile = Get-Item -LiteralPath $outputPath
    $outputFile.IsReadOnly = $false
}
