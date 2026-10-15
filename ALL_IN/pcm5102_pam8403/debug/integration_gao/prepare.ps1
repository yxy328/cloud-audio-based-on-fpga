[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$rootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Reuse the current project's sources and constraints instead of an old top.
# Gowin accepts version="1" in older project headers, XML libraries need 1.0.
$projectText = Get-Content -LiteralPath (Join-Path $rootDir 'PCM5102_PAM8403.gprj') -Raw
[xml] $project = $projectText.Replace('<?xml version="1"', '<?xml version="1.0"')
foreach ($source in $project.Project.FileList.File) {
    $source.path = if ($source.path -eq 'src/top.v') { 'src/top_probe.v' } else { '../../' + $source.path }
}
$gaoFile = $project.CreateElement('File')
$gaoFile.SetAttribute('path', 'INTEGRATION_GAO.gao')
$gaoFile.SetAttribute('type', 'file.gao')
$gaoFile.SetAttribute('enable', '1')
[void] $project.Project.FileList.AppendChild($gaoFile)
$project.Save((Join-Path $PSScriptRoot 'INTEGRATION_GAO.gprj'))

[xml] $gao = Get-Content -LiteralPath (Join-Path $rootDir 'debug/audio_gao/AUDIO_GAO.gao') -Raw
$core = $gao.GAO_CONFIG.AoCore
$core.SetAttribute('storage_depth', '4096')
$core.SetAttribute('capture_amount', '4096')
$core.SetAttribute('trigger_pos', '3072')
$signalList = $core.SelectSingleNode('SignalList')
$signalList.RemoveAll()
$probes = [ordered]@{
    key_s1=1; key_s2=1; resetn=1; touch_ready=1;
    touch_out=8; touch_keys=8; fsr_pitch_mode=1; fsr_gain=16;
    frame_ce=1; guitar_scaled_sample=16; touch_mix0=16;
    gesture_sample=16; audio_sample=16; gesture_ready=1;
    i2s_bck=1; i2s_lrck=1; i2s_din=1
}
# Plain wire aliases can disappear during optimization. Observe each signal
# through a retained register, uniformly delayed by one 50MHz clock.
$probeCode = @('// Diagnostic observations: one master-clock delay, no audio control changes.')
foreach ($name in $probes.Keys) {
    # One-bit vectors keep an explicit [0] net name in Gowin's netlist.
    $range = '[' + ($probes[$name]-1) + ':0] '
    $probeCode += "    (* syn_preserve = 1, syn_keep = 1 *) reg ${range}probe_$name;"
}
$probeCode += '    always @(posedge clk) begin'
$probeCode += '        if (!resetn) begin'
foreach ($name in $probes.Keys) { $probeCode += "            probe_$name <= 0;" }
$probeCode += '        end else begin'
foreach ($name in $probes.Keys) { $probeCode += "            probe_$name <= $name;" }
$probeCode += '        end'
$probeCode += '    end'
$originalTop = Get-Content -LiteralPath (Join-Path $rootDir 'src/top.v') -Raw
$probeBlock = $probeCode -join "`n"
$probeTop = [regex]::Replace($originalTop, '(?m)^endmodule\s*$', "$probeBlock`nendmodule`n")
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'src') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'src/top_probe.v') -Value $probeTop -Encoding utf8
foreach ($name in $probes.Keys) {
    $bus = $gao.CreateElement('Bus')
    $bus.SetAttribute('capture_enable', 'true')
    $bus.SetAttribute('name', $name)
    for ($bit=$probes[$name]-1; $bit -ge 0; $bit--) {
        $signal = $gao.CreateElement('Signal')
        $signal.InnerText = "probe_$name[$bit]"
        [void] $bus.AppendChild($signal)
    }
    [void] $signalList.AppendChild($bus)
}
$gao.GAO_CONFIG.GAO_ID = '0011100100110101'
$gao.Save((Join-Path $PSScriptRoot 'INTEGRATION_GAO.gao'))
$probeWidth = ($probes.Values | Measure-Object -Sum).Sum
Write-Host "Prepared current-top GAO: $probeWidth sampled bits, 4096 samples at 50MHz."
