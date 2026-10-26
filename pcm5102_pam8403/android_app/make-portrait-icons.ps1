param(
    [Parameter(Mandatory = $true)][string]$PortraitsDir
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

function Read-Matte {
    param([System.Drawing.Bitmap]$Image)
    $inset = [Math]::Max(2, [int]($Image.Width / 24))
    $r = 0
    $g = 0
    $b = 0
    $pts = @(
        @($inset, $inset),
        @(($Image.Width - 1 - $inset), $inset),
        @($inset, ($Image.Height - 1 - $inset)),
        @(($Image.Width - 1 - $inset), ($Image.Height - 1 - $inset))
    )
    foreach ($pt in $pts) {
        $c = $Image.GetPixel($pt[0], $pt[1])
        $r += $c.R
        $g += $c.G
        $b += $c.B
    }
    return '#{0:X2}{1:X2}{2:X2}' -f [int]($r / 4), [int]($g / 4), [int]($b / 4)
}

Push-Location $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$resRoot = Join-Path $PSScriptRoot 'app\src\main\res'
$dir = [System.IO.Path]::GetFullPath($PortraitsDir)

# random bijection: first five picks become adaptive foregrounds (mdpi..xxxhdpi),
# last five become legacy full-bleed icons for the same density order
$order = @(0..9) | Sort-Object { Get-Random }
$densities = @(
    @{ Name = 'mdpi'; Scale = 1.0 },
    @{ Name = 'hdpi'; Scale = 1.5 },
    @{ Name = 'xhdpi'; Scale = 2.0 },
    @{ Name = 'xxhdpi'; Scale = 3.0 },
    @{ Name = 'xxxhdpi'; Scale = 4.0 }
)
for ($i = 0; $i -lt 5; $i++) {
    $scale = $densities[$i].Scale
    $dirName = 'mipmap-' + $densities[$i].Name
    $fgPath = Join-Path $dir ('p{0}.png' -f $order[$i])
    $lgPath = Join-Path $dir ('p{0}.png' -f $order[$i + 5])
    $fg = New-Object System.Drawing.Bitmap($fgPath)
    $lg = New-Object System.Drawing.Bitmap($lgPath)
    $matte = Read-Matte $fg
    Save-ScaledIcon $fg ([int](108 * $scale)) ([int](66 * $scale)) (Join-Path $resRoot ($dirName + '\ic_launcher_foreground.png')) -Fill $matte
    Save-ScaledIcon $lg ([int](48 * $scale)) 0 (Join-Path $resRoot ($dirName + '\ic_launcher.png'))
    $valuesDir = Join-Path $resRoot ('values-' + $densities[$i].Name)
    New-Item -ItemType Directory -Force -Path $valuesDir | Out-Null
    $colors = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n"
    $colors += "<resources>`n"
    $colors += "    <color name=`"ic_launcher_background`">" + $matte + "</color>`n"
    $colors += "</resources>`n"
    Set-Content -LiteralPath (Join-Path $valuesDir 'colors.xml') -Value $colors -Encoding UTF8
    Write-Output ('{0}: foreground=p{1} legacy=p{2} matte={3}' -f $densities[$i].Name, $order[$i], $order[$i + 5], $matte)
    $fg.Dispose()
    $lg.Dispose()
}
Pop-Location
Write-Output 'portrait icons generated'
