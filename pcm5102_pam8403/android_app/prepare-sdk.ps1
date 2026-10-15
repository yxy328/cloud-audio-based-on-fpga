$ErrorActionPreference = 'Stop'
# Download only local build prerequisites from Google's official SDK repository.
# Packages match Android API 35 platform r02 and build-tools 35.0.0.
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path tools,tools\sdk\platforms,tools\sdk\build-tools | Out-Null
    $packages = @(
        @{ Name='platform-35_r02.zip'; Hash='0BB560A90A7A2CBD0DD8348224D518B638FE7949'; Target='tools\sdk\platforms' },
        @{ Name='build-tools_r35_windows.zip'; Hash='AF059BB67CF7786F45EE0DB85E2D24985DF1B4B6'; Target='tools\sdk\build-tools' }
    )
    foreach ($package in $packages) {
        $file=Join-Path tools $package.Name
        if (!(Test-Path -LiteralPath $file)) { Invoke-WebRequest -Uri ('https://dl.google.com/android/repository/'+$package.Name) -OutFile $file }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA1).Hash -ne $package.Hash) { throw ('SDK checksum mismatch: '+$package.Name) }
        Expand-Archive -LiteralPath $file -DestinationPath $package.Target -Force
    }
    Write-Host 'Local Android SDK ready. Run .\test-core.ps1 and .\build-apk.ps1.'
} finally { Pop-Location }
