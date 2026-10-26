param(
    [string]$PortraitsDir = 'build\portraits'
)
$ErrorActionPreference = 'Stop'

function Draw-Medallion {
    param([System.Drawing.Graphics]$G, [string]$PortraitPath, [float]$Cx, [float]$Cy, [float]$D, [int]$RingPx)
    $rect = New-Object System.Drawing.RectangleF(($Cx - $D / 2), ($Cy - $D / 2), $D, $D)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse($rect)
    $G.SetClip($path)
    $G.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $p = [System.Drawing.Image]::FromFile($PortraitPath)
    $G.DrawImage($p, $rect)
    $p.Dispose()
    $G.ResetClip()
    $pen = New-Object System.Drawing.Pen(([System.Drawing.ColorTranslator]::FromHtml('#e8447f')), $RingPx)
    $G.DrawEllipse($pen, $rect)
    $pen.Dispose()
}

Push-Location $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$srcDir = [System.IO.Path]::GetFullPath($PortraitsDir)
$assets = Join-Path $PSScriptRoot 'app\src\main\assets'

for ($i = 0; $i -lt 10; $i++) {
    Copy-Item -LiteralPath (Join-Path $srcDir ("p{0}.png" -f $i)) -Destination (Join-Path $assets ("portrait_{0}.png" -f $i)) -Force
}
$backdropPath = Join-Path $assets 'backdrop.png'
$backupPath = Join-Path $PSScriptRoot 'design\backdrop_neon_backup.png'
if (!(Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $backdropPath -Destination $backupPath
}
$bd = New-Object System.Drawing.Bitmap($backdropPath)
$g = [System.Drawing.Graphics]::FromImage($bd)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
# top-right medallion peeks through the transparent header; right-middle one peeks
# through the gaps between cards
Draw-Medallion $g (Join-Path $srcDir 'p2.png') ($bd.Width * 0.80) ($bd.Height * 0.10) ($bd.Width * 0.34) 8
Draw-Medallion $g (Join-Path $srcDir 'p0.png') ($bd.Width * 0.86) ($bd.Height * 0.46) ($bd.Width * 0.40) 8
$g.Dispose()
$tmpPath = $backdropPath + '.tmp'
$bd.Save($tmpPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bd.Dispose()
Move-Item -LiteralPath $tmpPath -Destination $backdropPath -Force
Pop-Location
Write-Output 'portraits copied and backdrop medallions composited'
