param(
    [Parameter(Mandatory = $true)][string]$SourceImage,
    [int]$HeroWidth = 1080
)
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$srcPath = [System.IO.Path]::GetFullPath($SourceImage)
$src = New-Object System.Drawing.Bitmap($srcPath)
$W = $src.Width
$H = $src.Height
# bottom strip is 10 equal squares, so its height equals one tenth of the width
$side = [int]($W / 10)
$topH = $H - $side
Write-Output ("source={0}x{1} side={2} topH={3}" -f $W, $H, $side, $topH)

function Save-Crop {
    param([System.Drawing.Bitmap]$Source, [System.Drawing.Rectangle]$Area, [int]$OutWidth, [string]$Path)
    $crop = $Source.Clone($Area, $Source.PixelFormat)
    if ($OutWidth -gt 0 -and $OutWidth -ne $crop.Width) {
        $ratio = $OutWidth / [float]$crop.Width
        $outH = [int]([Math]::Round($crop.Height * $ratio))
        $scaled = New-Object System.Drawing.Bitmap($OutWidth, $outH)
        $gr = [System.Drawing.Graphics]::FromImage($scaled)
        $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $gr.DrawImage($crop, (New-Object System.Drawing.Rectangle(0, 0, $OutWidth, $outH)))
        $gr.Dispose()
        $crop.Dispose()
        $crop = $scaled
    }
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $crop.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("{0} {1}x{2}" -f $Path, $crop.Width, $crop.Height)
    $crop.Dispose()
}

$topRect = New-Object System.Drawing.Rectangle(0, 0, $W, $topH)
Save-Crop $src $topRect $HeroWidth (Join-Path $PSScriptRoot 'app\src\main\assets\hero.png')

$outDir = Join-Path $PSScriptRoot 'build\portraits'
for ($i = 0; $i -lt 10; $i++) {
    $rect = New-Object System.Drawing.Rectangle(($i * $side), $topH, $side, $side)
    Save-Crop $src $rect 0 (Join-Path $outDir ("p{0}.png" -f $i))
}
$src.Dispose()
Pop-Location
Write-Output 'art extracted'
