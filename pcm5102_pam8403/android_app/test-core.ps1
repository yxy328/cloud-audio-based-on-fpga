$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path build\core | Out-Null
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\AdsrProfile.java core_test\AdsrProfileTest.java app\src\main\java\cn\fpga\score\SongCodec.java app\src\main\java\cn\fpga\score\SppLink.java core_test\SongCodecTest.java core_test\SppLinkTest.java core_test\android\bluetooth\BluetoothSocket.java core_test\android\bluetooth\BluetoothDevice.java
    if ($LASTEXITCODE -ne 0) { throw 'Core test compilation failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\VoiceBend.java core_test\VoiceBendTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Voice bend test compilation failed' }
    & java -cp build\core cn.fpga.score.VoiceBendTest
    if ($LASTEXITCODE -ne 0) { throw 'Voice bend tests failed' }
    & java -cp build\core cn.fpga.score.AdsrProfileTest
    if ($LASTEXITCODE -ne 0) { throw 'ADSR tests failed' }
    & java -cp build\core cn.fpga.score.SongCodecTest
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }
    & java -cp build\core cn.fpga.score.SppLinkTest
    if ($LASTEXITCODE -ne 0) { throw 'SPP transport tests failed' }
} finally { Pop-Location }
