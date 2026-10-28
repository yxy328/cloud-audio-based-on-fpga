"""Update current-version documentation after verify_release.py succeeds."""
from pathlib import Path
import json

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parent
data = json.loads((HERE / 'release.json').read_text(encoding='utf-8'))
assert data['setup_violations'] == data['hold_violations'] == 0
res = data['resources']
summary = ('单曲由128条扩到256条；120首曲库中19首保留原谱反复，最长252条、约104秒。'
           '整机BSRAM仍54/56、DSP仍25，音游支持256连击及384000分。'
           '超过128条须配套更新FPGA位流；未安装手机或烧录。')


def prepend(path, text):
    old = path.read_text(encoding='utf-8')
    if not old.startswith(text):
        path.write_text(text + '\n\n' + old, encoding='utf-8')


prepend(REPO / 'README.md', '**2026-10-28 当前 App / FPGA：Code46，单曲256条。** ' + summary +
        '见[安装与位流](pcm5102_pam8403/reports/score256_20261028/README.md)。以下为此前版本记录。')
prepend(PROJECT / 'README.md', '**2026-10-28 当前 App / FPGA：Code46，单曲256条。** ' + summary +
        '曲谱页新增“载入长曲 · 104秒”。见[安装与位流](reports/score256_20261028/README.md)。以下为此前版本记录。')
prepend(PROJECT / 'android_app/README.md', '**2026-10-28 当前安装包：1.45-score256 / Code46。** ' + summary +
        '[安装包](dist/FPGA-Music-Score256-Code46.apk)与默认Unified.apk相同；曲谱页可直接“载入长曲 · 104秒”。'
        '见[配套位流与验证](../reports/score256_20261028/README.md)。以下为此前版本记录。')
resource_text = ' / '.join(f'{k} {res[k]["used"]}' for k in ['Logic', 'CLS', 'Register', 'BSRAM', 'DSP'])
prepend(PROJECT / 'VERIFICATION.md', '**2026-10-28 Code46 单曲256条：** ' + resource_text +
        f'，剩{data["remaining_cls"]} CLS；50MHz setup/hold违例0/0，余量 '
        f'+{data["setup_slack_ns"]:.3f}/+{data["hold_slack_ns"]:.3f}ns。'
        '曲谱本身仍2块BSRAM，256条UART/原子性/四类判定与音频回归、App核心、频谱逐拍等价和路由网表扫描通过。'
        '未安装或烧录，详见[本轮报告](reports/score256_20261028/README.md)。')
change = REPO / 'docs/CHANGELOG.md'
old = change.read_text(encoding='utf-8')
entry = ('## 2026-10-28 · Code46：单曲256条\n\n' + summary +
         '写入标记改为暂存区清零检测，计分ROM保留原物理块；频谱复用已有阶段寄存前值，数值和周期逐拍等价。'
         '见[配套产物与完整验证](../pcm5102_pam8403/reports/score256_20261028/README.md)。\n\n')
if entry not in old:
    change.write_text(old.replace('# 版本记录\n', '# 版本记录\n\n' + entry, 1), encoding='utf-8')
rhythm = PROJECT / 'RHYTHM_GAME.md'
text = rhythm.read_text(encoding='utf-8').replace('（Code44）', '（Code46）', 1)
text = text.replace('当前 App **1.44-library120 / Code45**：[安装包](android_app/dist/FPGA-Music-Library120-Code45.apk)。本页玩法沿用 Code44 FPGA，',
                    '当前 App **1.45-score256 / Code46**：[安装包](android_app/dist/FPGA-Music-Score256-Code46.apk)，超过128条需配套Code46 FPGA。')
rhythm.write_text(text, encoding='utf-8')
prepend(rhythm, '**Code46 容量：每首最多256条事件，满分384000，连击/最高连击/Miss均支持256。** '
        '曲谱页“载入长曲 · 104秒”可直接载入最长曲目，再匹配十二键下载。')
bend = PROJECT / 'SCORE_BEND.md'
bend.write_text(bend.read_text(encoding='utf-8').replace('总容量 128 条', 'Code46 配套时总容量 256 条（旧位流128条）'), encoding='utf-8')
library = PROJECT / 'android_app/SONG_LIBRARY.md'
history = library.read_text(encoding='utf-8').split('# 历史记录：', 1)[1]
library.write_text('''# 120首共享曲库：单曲256条（Code46）

2026-10-28，App **1.45-score256 / Code46**：[安装包](dist/FPGA-Music-Score256-Code46.apk)，默认入口为 [FPGA-Music-Unified.apk](dist/FPGA-Music-Unified.apk)。**超过128条需要配套Code46 FPGA位流。**

## 播放与音游

音游、下落指引和自动演奏共用同一份板上已提交曲谱。选择曲目、点击“匹配十二键并下载所选曲目”，收到提交成功确认后：PLAY跟谱演奏并计分；自动演奏试听不计分。只载入或更换下拉选项不会改变板上曲谱。

曲谱页新增 **“载入长曲 · 104秒”**，自动选中并载入最长曲目，之后仍需点击匹配十二键并下载。

## 曲库与长度

合计120首，青铜/白银/黄金各40首。原九首和默认白银《伦敦桥》保留；新增来源111首中58首保留全部旋律、53首明确标注节选。19首现在按原谱展开反复，13首超过旧128条容量，最长252条、103.571秒。没有靠重复收录或放慢速度凑数量。

单曲最多 **256条音符/和弦/休止事件**，每条1～60000ms；实际曲长取决于节奏。范围仍为MIDI60～72、最多十二种映射音高，原九首保持七键兼容。全曲和反复能容纳时优先保留；否则选取完整记谱小节并在标题及说明中标注节选范围，不折叠八度、不切断边界连音。

普通曲库使用AUTO类型，默认≥500ms为HOLD、短音为TAP；四类音符练习谱及note_type CSV继续支持DRAG/FLICK。CSV/MIDI导入、CSV导出和弯音目标均支持256条。

## FPGA资源

整个曲库保存在手机，板上只保存当前一首；仅增加手机曲目数量不增加FPGA资源。本轮单曲128→256属于FPGA容量扩展，需要新位流，但利用原物理块的空余深度，曲谱仍 **2块BSRAM**，整机仍54/56，DSP仍25。下载前清空暂存区代替写入标记，保留乱序覆盖和原子提交；计分与时间轴同步扩展。实际资源和50MHz时序见[本轮报告](../reports/score256_20261028/README.md)。

来源、逐曲版本/时长/指纹见[说明](third_party/oneill/README.md)和[catalogue.json](third_party/oneill/catalogue.json)。新增曲保留英文原名，不包含录音或现代伴奏。未安装手机或做真实HC-05试玩。

---

# 历史记录：''' + history, encoding='utf-8')
source = PROJECT / 'android_app/third_party/oneill/README.md'
text = source.read_text(encoding='utf-8')
start = text.index('The mechanical conversion')
end = text.index('The APK contains', start)
text = text[:start] + '''The mechanical conversion uses music21 10.5.1 at build time only. It prefers
full melodies with notated repeats expanded when they fit the 256-event limit.
If repeats are ambiguous or exceed capacity, it keeps the single-pass edition,
taking first-pass endings. Ties are joined, grace ornaments omitted, and one
constant transposition fits C4-C5 without octave folding. Intervals and relative
durations are preserved; practice tempo is in quarter notes per minute.

For wider/longer works one labelled excerpt of 4/8/12/16/24/32 complete written
bars may be used. Its title has “（节选）”; its exact range counts pickups in the
single-pass edition after later-pass endings are removed. Boundaries never cut
ties. Each source tune appears once; tempo, key or excerpt variants do not
inflate the catalogue. Code46 retains all 111 source IDs, expands repeats for
19 tunes, and supports up to 256 events. The other nine original library entries
remain unchanged.

''' + text[end:]
source.write_text(text, encoding='utf-8')
print('Updated Code46 documentation with verified resource and timing results')
