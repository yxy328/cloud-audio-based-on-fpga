param(
    [Parameter(Mandatory = $true)][string]$SourceImage
)
$ErrorActionPreference = 'Stop'

function Save-ScaledIcon {
    param([System.Drawing.Image]$Source, [int]$Canvas, [int]$Inner, [string]$Path, [string]$Fill = '')
    $bmp = New-Object System.Drawing.Bitmap($Canvas, $Canvas)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    if ($Fill -ne '') {
        $gr.Clear([System.Drawing.ColorTranslator]::FromHtml($Fill))
    }
    else {
        $gr.Clear([System.Drawing.Color]::Transparent)
    }
    $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $gr.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    if ($Inner -le 0) {
        $dest = New-Object System.Drawing.RectangleF(0, 0, $Canvas, $Canvas)
    }
    else {
        $off = ($Canvas - $Inner) / 2.0
        $dest = New-Object System.Drawing.RectangleF($off, $off, $Inner, $Inner)
    }
    $gr.DrawImage($Source, $dest)
    $gr.Dispose()
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

Push-Location $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$srcPath = [System.IO.Path]::GetFullPath($SourceImage)
$src = [System.Drawing.Image]::FromFile($srcPath)
$srcBmp = New-Object System.Drawing.Bitmap($src)

# Adaptive icon base color: mean of the four inset corner samples of the source
# (the artwork's own pink border); foreground gets the same color as matte so the
# launcher mask ring stays seamless.
$inset = [Math]::Max(3, [int]($srcBmp.Width / 50))
$r = 0
$g = 0
$b = 0
$corners = @(
    @($inset, $inset),
    @(($srcBmp.Width - 1 - $inset), $inset),
    @($inset, ($srcBmp.Height - 1 - $inset)),
    @(($srcBmp.Width - 1 - $inset), ($srcBmp.Height - 1 - $inset))
)
foreach ($pt in $corners) {
    $c = $srcBmp.GetPixel($pt[0], $pt[1])
    $r += $c.R
    $g += $c.G
    $b += $c.B
}
$bg = '#{0:X2}{1:X2}{2:X2}' -f [int]($r / 4), [int]($g / 4), [int]($b / 4)
Write-Output ("background=" + $bg + " source=" + $src.Width + "x" + $src.Height)

$densities = @(
    @{ Name = 'mdpi'; Scale = 1.0 },
    @{ Name = 'hdpi'; Scale = 1.5 },
    @{ Name = 'xhdpi'; Scale = 2.0 },
    @{ Name = 'xxhdpi'; Scale = 3.0 },
    @{ Name = 'xxxhdpi'; Scale = 4.0 }
)
$resRoot = Join-Path $PSScriptRoot 'app\src\main\res'
foreach ($d in $densities) {
    $scale = $d.Scale
    $dirName = 'mipmap-' + $d.Name
    Save-ScaledIcon $src ([int](48 * $scale)) 0 (Join-Path $resRoot ($dirName + '\ic_launcher.png'))
    Save-ScaledIcon $src ([int](108 * $scale)) ([int](66 * $scale)) (Join-Path $resRoot ($dirName + '\ic_launcher_foreground.png')) -Fill $bg
}

$anydpi = Join-Path $resRoot 'mipmap-anydpi-v26'
New-Item -ItemType Directory -Force -Path $anydpi | Out-Null
$values = Join-Path $resRoot 'values'
New-Item -ItemType Directory -Force -Path $values | Out-Null
$colors = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n"
$colors += "<resources>`n"
$colors += "    <color name=`"ic_launcher_background`">" + $bg + "</color>`n"
$colors += "</resources>`n"
Set-Content -LiteralPath (Join-Path $values 'colors.xml') -Value $colors -Encoding UTF8
$xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n"
$xml += "<adaptive-icon xmlns:android=`"http://schemas.android.com/apk/res/android`">`n"
$xml += "    <background android:drawable=`"@color/ic_launcher_background`" />`n"
$xml += "    <foreground android:drawable=`"@mipmap/ic_launcher_foreground`" />`n"
$xml += "</adaptive-icon>`n"
Set-Content -LiteralPath (Join-Path $anydpi 'ic_launcher.xml') -Value $xml -Encoding UTF8

$srcBmp.Dispose()
$src.Dispose()
Pop-Location
Write-Output 'launcher icons generated'
