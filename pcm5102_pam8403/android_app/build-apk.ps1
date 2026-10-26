param(
    [string]$SdkPath = (Join-Path $PSScriptRoot 'tools\sdk'),
    [string]$OutputApk = 'dist\FPGA-Music-Unified.apk'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $sdkAbsolute = [System.IO.Path]::GetFullPath($SdkPath)
    $androidJar = Join-Path $sdkAbsolute 'platforms\android-35\android.jar'
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdkAbsolute 'build-tools') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (!(Test-Path -LiteralPath $androidJar) -or !$buildTools) { throw 'Missing SDK. Run .\prepare-sdk.ps1 first, or specify -SdkPath.' }
    $jdkBin = Split-Path (Get-Command javac.exe -ErrorAction Stop).Source
    $java = Join-Path $jdkBin 'java.exe'
    New-Item -ItemType Directory -Force -Path build\classes,build\dex,dist | Out-Null
    $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'build')) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($outputDirectory in @('classes','dex')) {
        $outputRoot = (Resolve-Path -LiteralPath (Join-Path $buildRoot $outputDirectory)).Path
        if (!$outputRoot.StartsWith($buildRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Build output escaped build directory' }
        Get-ChildItem -LiteralPath $outputRoot -Recurse -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    }
    $sources = @(Get-ChildItem -LiteralPath app\src\main\java -Filter '*.java' -Recurse | ForEach-Object FullName)
    & (Join-Path $jdkBin 'javac.exe') --release 8 -Xlint:-options -encoding UTF-8 -classpath $androidJar -d build\classes @sources
    if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
    $classes = @(Get-ChildItem -LiteralPath build\classes -Filter '*.class' -Recurse | ForEach-Object FullName)
    & $java -cp (Join-Path $buildTools.FullName 'lib\d8.jar') com.android.tools.r8.D8 --release --min-api 29 --lib $androidJar --output build\dex @classes
    if ($LASTEXITCODE -ne 0) { throw 'D8 failed' }
    & (Join-Path $buildTools.FullName 'aapt2.exe') compile --dir app\src\main\res -o build\res.zip
    if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }
    & (Join-Path $buildTools.FullName 'aapt2.exe') link -I $androidJar --manifest app\src\main\AndroidManifest.xml --min-sdk-version 29 --target-sdk-version 35 -o build\unsigned.apk build\res.zip
    if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open((Join-Path $PSScriptRoot 'build\unsigned.apk'), [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $PSScriptRoot 'build\dex\classes.dex'),'classes.dex') | Out-Null
        # 主题素材（PNG）打进 assets/，运行时用 BitmapFactory 读取
        $assetsDir = Join-Path $PSScriptRoot 'app\src\main\assets'
        if (Test-Path -LiteralPath $assetsDir) {
            $assetsRoot = (Resolve-Path -LiteralPath $assetsDir).Path.TrimEnd('\')
            Get-ChildItem -LiteralPath $assetsRoot -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($assetsRoot.Length + 1).Replace('\', '/')
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "assets/$rel") | Out-Null
            }
        }
    } finally { $zip.Dispose() }
    & (Join-Path $buildTools.FullName 'zipalign.exe') -f -p 4 build\unsigned.apk build\aligned.apk
    if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }
    if (!(Test-Path -LiteralPath tools\debug.keystore)) {
        & (Join-Path $jdkBin 'keytool.exe') -genkeypair -keystore tools\debug.keystore -storepass android -keypass android -alias androiddebugkey -dname 'CN=FPGA Score Debug,O=Local,C=CN' -keyalg RSA -keysize 2048 -validity 10000
        if ($LASTEXITCODE -ne 0) { throw 'Debug signing key generation failed' }
    }
    # Keep the existing stable v1.6 APK. Allow a named feature build without
    # overwriting the event-take preview or requiring event-take firmware.
    & $java -jar (Join-Path $buildTools.FullName 'lib\apksigner.jar') sign --ks tools\debug.keystore --ks-pass pass:android --key-pass pass:android --out $OutputApk build\aligned.apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signing failed' }
    & $java -jar (Join-Path $buildTools.FullName 'lib\apksigner.jar') verify --verbose $OutputApk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
    & (Join-Path $buildTools.FullName 'aapt2.exe') dump badging $OutputApk
    if ($LASTEXITCODE -ne 0) { throw 'APK manifest verification failed' }
    Get-FileHash -LiteralPath $OutputApk -Algorithm SHA256
} finally { Pop-Location }
