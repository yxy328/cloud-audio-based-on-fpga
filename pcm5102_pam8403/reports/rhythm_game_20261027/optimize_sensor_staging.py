from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/sensor_poly_audio.v';s=p.read_text(encoding='utf-8')
(R/'sim/sensor_staging_reference.v').write_text(s.replace('module sensor_poly_audio #(','module sensor_staging_reference #('),encoding='utf-8')
s=s.replace('(* syn_ramstyle="distributed_ram" *) reg [132:0] configs[0:3];','(* syn_ramstyle="block_ram" *) reg [132:0] configs[0:3];')
s=s.replace('                configs[config_wr]<={adsr_config,control_timbre};config_wr<=config_wr+1\'b1;','                config_wr<=config_wr+1\'b1;')
s=s.replace('    wire [164:0] next_event={configs[config_tags[rd]],pitches[rd]};','''    // Prefetch the following head, including tags written by either producer
    // on this edge. Explicit same-address forwarding preserves the original
    // queue's zero extra pop latency for simultaneous IR/gesture events.
    wire [1:0] prefetch_rd=pop ? rd+2'd1 : rd;
    wire [1:0] prefetch_tag=(take_ir && wr==prefetch_rd) ||
        (take_gesture && second_wr==prefetch_rd) ? config_wr : config_tags[prefetch_rd];
    wire config_collision=pushes!=0 && prefetch_tag==config_wr;
    reg [132:0] config_q,config_written;
    reg config_forward;
    always @(posedge clk)begin
        if(resetn && pushes!=0)begin
            configs[config_wr]<={adsr_config,control_timbre};
            config_written<={adsr_config,control_timbre};
        end
        if(!config_collision)config_q<=configs[prefetch_tag];
        config_forward<=config_collision;
    end
    wire [164:0] next_event={config_forward ? config_written : config_q,pitches[rd]};''')
p.write_text(s,encoding='utf-8')
p=R/'tools/run_sim.ps1';s=p.read_text(encoding='utf-8');s=s.replace("'src/sensor_poly_audio.v'","'sim/sensor_staging_reference.v','src/sensor_poly_audio.v'");p.write_text(s,encoding='utf-8')
# Every new build freezes its process settings together with its RTL.
config=R/'impl/PCM5102_UNIFIED_process_config.json';config.parent.mkdir(exist_ok=True)
source=R/'sim/build/unified/rhythm_game_native_wide/build_inputs/PCM5102_UNIFIED_process_config.json'
config.write_bytes(source.read_bytes())
p=R/'tools/check_unified_build.ps1';s=p.read_text(encoding='utf-8')
anchor='Copy-Item -LiteralPath "$projectDir/src" -Destination $target -Recurse'
s=s.replace(anchor,'''$rhythmProcess=Join-Path $projectDir 'impl/PCM5102_UNIFIED_process_config.json'
if(Test-Path -LiteralPath $rhythmProcess){
    New-Item -ItemType Directory -Path "$snapshot/build_inputs" -Force | Out-Null
    Copy-Item -LiteralPath $rhythmProcess -Destination "$snapshot/build_inputs/PCM5102_UNIFIED_process_config.json"
}
'''+anchor);p.write_text(s,encoding='utf-8')
print('Atomic sensor staging moved to native-wide BSRAM; build config frozen')
