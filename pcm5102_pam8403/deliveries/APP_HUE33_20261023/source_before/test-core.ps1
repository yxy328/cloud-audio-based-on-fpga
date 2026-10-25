$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force -Path build\core | Out-Null
    & javac --release 8 -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\PerformanceParams.java core_test\PerformanceParamsTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Performance parameters compilation failed' }
    & java -cp build\core cn.fpga.score.PerformanceParamsTest
    if ($LASTEXITCODE -ne 0) { throw 'Performance parameters tests failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\LedState.java app\src\main\java\cn\fpga\score\LedFrame.java core_test\LedProtocolTest.java
    if ($LASTEXITCODE -ne 0) { throw 'LED protocol compilation failed' }
    & java -cp build\core cn.fpga.score.LedProtocolTest
    if ($LASTEXITCODE -ne 0) { throw 'LED protocol tests failed' }
    if(Test-Path -LiteralPath ../sim/build/led_visual_protocol.txt){
        $ledFixtures = @('../sim/build/led_visual_protocol.txt')
        if(Test-Path -LiteralPath ../sim/build/led_top_preview.txt){ $ledFixtures += '../sim/build/led_top_preview.txt' }
        & java -cp build\core cn.fpga.score.LedProtocolTest @ledFixtures
        if ($LASTEXITCODE -ne 0) { throw 'RTL LED protocol integration failed' }
    }
    & javac --release 8 -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\TakeStatus.java core_test\TakeStatusTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Take status compilation failed' }
    & java -cp build\core cn.fpga.score.TakeStatusTest
    if ($LASTEXITCODE -ne 0) { throw 'Take status tests failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -cp build\core -d build\core app\src\main\java\cn\fpga\score\AdsrProfile.java core_test\AdsrProfileTest.java app\src\main\java\cn\fpga\score\SongCodec.java app\src\main\java\cn\fpga\score\AudioRecording.java app\src\main\java\cn\fpga\score\SppLink.java core_test\SongCodecTest.java core_test\SppLinkTest.java core_test\android\bluetooth\BluetoothSocket.java core_test\android\bluetooth\BluetoothDevice.java
    if ($LASTEXITCODE -ne 0) { throw 'Core test compilation failed' }
    & javac --release 8 -encoding UTF-8 -cp build\core -d build\core app\src\main\java\cn\fpga\score\RecordingSupport.java app\src\main\java\cn\fpga\score\TakeStatus.java app\src\main\java\cn\fpga\score\ChromaticKeys.java app\src\main\java\cn\fpga\score\PhoneTake.java app\src\main\java\cn\fpga\score\PhoneTakeStore.java core_test\RecordingSupportTest.java core_test\PhoneTakeTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Recording support/MIDI compilation failed' }
    & java -cp build\core cn.fpga.score.RecordingSupportTest
    if ($LASTEXITCODE -ne 0) { throw 'Recording support tests failed' }
    & java -cp build\core cn.fpga.score.PhoneTakeTest
    if ($LASTEXITCODE -ne 0) { throw 'Event MIDI tests failed' }
    & javac --release 8 -encoding UTF-8 -cp build\core -d build\core app\src\main\java\cn\fpga\score\SongLibrary.java core_test\SongLibraryTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Song library compilation failed' }
    & java -cp build\core cn.fpga.score.SongLibraryTest
    if ($LASTEXITCODE -ne 0) { throw 'Song library tests failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\VoiceBend.java core_test\VoiceBendTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Voice bend test compilation failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\DeviceControls.java core_test\DeviceControlsTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Device controls compilation failed' }
    & javac --release 8 -Xlint:-options -encoding UTF-8 -d build\core app\src\main\java\cn\fpga\score\AudioRecording.java core_test\AudioRecordingTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Audio recording test compilation failed' }
    & javac --release 8 -encoding UTF-8 -cp build\core -d build\core app\src\main\java\cn\fpga\score\ControlState.java app\src\main\java\cn\fpga\score\TakeWorkflow.java core_test\ControlStateTest.java core_test\TakeWorkflowTest.java core_test\SppAudioTest.java core_test\ChromaticKeysTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Sidebar state compilation failed' }
    foreach ($sidebarTest in @('ControlStateTest','TakeWorkflowTest','SppAudioTest','ChromaticKeysTest')) {
        & java -cp build\core "cn.fpga.score.$sidebarTest"
        if ($LASTEXITCODE -ne 0) { throw "$sidebarTest failed" }
    }
    & java -cp build\core cn.fpga.score.DeviceControlsTest
    if ($LASTEXITCODE -ne 0) { throw 'Device controls tests failed' }
    & java -cp build\core cn.fpga.score.VoiceBendTest
    if ($LASTEXITCODE -ne 0) { throw 'Voice bend tests failed' }
    & java -cp build\core cn.fpga.score.AdsrProfileTest
    if ($LASTEXITCODE -ne 0) { throw 'ADSR tests failed' }
    & java -cp build\core cn.fpga.score.SongCodecTest
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }
    & java -cp build\core cn.fpga.score.SppLinkTest
    if ($LASTEXITCODE -ne 0) { throw 'SPP transport tests failed' }
    & java -cp build\core cn.fpga.score.AudioRecordingTest
    if ($LASTEXITCODE -ne 0) { throw 'Audio recording tests failed' }
    if(Test-Path -LiteralPath ../sim/build/audio_record_stream.bin){
        & java -cp build\core cn.fpga.score.AudioRecordingTest ../sim/build/audio_record_stream.bin
        if ($LASTEXITCODE -ne 0) { throw 'RTL audio recording integration failed' }
    }
    if((Test-Path -LiteralPath ../sim/build/audio_record_top.bin) -and (Test-Path -LiteralPath ../sim/build/audio_record_top_expected.txt)){
        & java -cp build\core cn.fpga.score.AudioRecordingTest ../sim/build/audio_record_top.bin ../sim/build/audio_record_top_expected.txt
        if ($LASTEXITCODE -ne 0) { throw 'Top live audio recording integration failed' }
    }
} finally { Pop-Location }
