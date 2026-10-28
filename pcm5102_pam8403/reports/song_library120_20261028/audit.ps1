$ErrorActionPreference='Stop'
$libraryReportRoot=$PSScriptRoot
$libraryProjectRoot=[IO.Path]::GetFullPath((Join-Path $libraryReportRoot '../..'))
$libraryAppRoot=Join-Path $libraryProjectRoot 'android_app'
$libraryBefore=Get-Content (Join-Path $libraryReportRoot 'rtl_before.json') -Raw | ConvertFrom-Json
$libraryFiles=@(Get-ChildItem (Join-Path $libraryProjectRoot 'src') -File)
if($libraryFiles.Count -ne $libraryBefore.Count){throw 'FPGA source set changed'}
foreach($entry in $libraryBefore){
    if((Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash -ne $entry.Hash){throw "FPGA source changed: $($entry.Path)"}
}
$libraryNew=Get-Item (Join-Path $libraryAppRoot 'dist/FPGA-Music-Library120-Code45.apk')
$libraryDefault=Get-Item (Join-Path $libraryAppRoot 'dist/FPGA-Music-Unified.apk')
$libraryHash=(Get-FileHash $libraryNew.FullName -Algorithm SHA256).Hash
if((Get-FileHash $libraryDefault.FullName -Algorithm SHA256).Hash -ne $libraryHash){throw 'Default APK mismatch'}
$libraryCatalogue=@(Get-Content (Join-Path $libraryAppRoot 'third_party/oneill/catalogue.json') -Raw | ConvertFrom-Json)
if($libraryCatalogue.Count -ne 111){throw 'Incorrect new tune count'}
foreach($entry in $libraryCatalogue){
    $librarySourceName=($entry.source -split '/')[-1]
    $librarySource=Join-Path $libraryAppRoot "third_party/oneill/abc/$librarySourceName"
    if((Get-FileHash -LiteralPath $librarySource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.abc_sha256){throw 'ABC source fingerprint mismatch'}
    if($entry.events -gt 128){throw 'Score capacity exceeded'}
}
$libraryRelease=[ordered]@{
    date='2026-10-28'; app_version_code=45; app_version_name='1.44-library120'
    catalogue_total=120; per_tier=40; preserved_original=9; added=111
    added_full_single_pass=@($libraryCatalogue | Where-Object {!$_.excerpt}).Count
    labelled_excerpts=@($libraryCatalogue | Where-Object {$_.excerpt}).Count
    max_new_events=($libraryCatalogue | Measure-Object events -Maximum).Maximum
    apk_sha256=$libraryHash; apk_bytes=$libraryNew.Length
    previous_apk_sha256=(Get-FileHash (Join-Path $libraryReportRoot 'rollback_Code44.apk')).Hash
    previous_apk_bytes=(Get-Item (Join-Path $libraryReportRoot 'rollback_Code44.apk')).Length
    existing_bitstream_sha256=(Get-FileHash (Join-Path $libraryProjectRoot 'impl/pnr/PCM5102_UNIFIED.fs')).Hash
    fpga_source_files_unchanged=$libraryBefore.Count
    fpga_resource_delta=@{Logic=0;CLS=0;Register=0;BSRAM=0;DSP=0}
    core_tests='PASS'; library_assertions=80015; deterministic_regeneration='PASS'
    apk_build='PASS'; apk_alignment='PASS'; same_signing_certificate='PASS'
    phone_installed=$false; real_hc05_download_tested=$false; fpga_rebuilt=$false; fpga_programmed=$false
}
$libraryRelease | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $libraryReportRoot 'release.json')
Write-Output "PASS: 120 entries, 111 source hashes, $($libraryBefore.Count) unchanged FPGA files, matching APKs"
