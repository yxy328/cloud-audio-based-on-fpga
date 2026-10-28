# 已完成：十二路可控 Code40

- 用户要求保留35 CLS；最终control12_width_final已满足。净增43 CLS，使用11482/11520，余38，预留35后可用3。
- 50 MHz、place2/route0/fan23，全布通，setup/hold零违例，原始最差裕量+0.478/+0.188 ns。BSRAM56/56、DSP25/28。
- Code40默认工程、APK和码流已同步；Code39覆盖项保存在rollback_Code39，与freeze.json/production_unchanged.json的原指纹核对通过。没有Git提交、安装App、烧录FPGA或写实物Flash。
- 正式入口：README.md、根目录CONTROL12.md、android_app/dist/FPGA-Music-Control12-Code40.apk、PCM5102_UNIFIED_CONTROL12_20261027.fs；旧REVIEW.md已标为历史实验记录。
- 最终23组RTL全部通过；final_verification.json含输入/日志指纹，width_final_top.log、width_final_units.log、width_final_compat.log、touch_width_equivalence.log为最终日志。
- App原位置核心回归app_core_installed_sources.log也全部通过；post_release_check.json核对安装源/全部复制文件/命名和默认APK与FS/Code39备份。正式测试脚本tools/test_control12.ps1运行23组RTL和App核心。
- 功能：K1..12映射/独立弯音/曲谱弯音/自动演奏/十二列指引；K13..16高音保留，16键发声保留。TAKE追加43字段，新版兼容旧33字段，1024事件容量保留。
- 最终优化：可信四位MAP快照及有界曲谱掩码索引、27x17触摸乘法与精确混音位宽、实时按键静态字节直接生成。768帧音频逐位等价及100000拍按键上行逐周期等价通过。没有采用中间RAM布局原型或COMPACT_MAP音高ROM实验。
- 所有失败/未采用实验均保留在构建记录中；packed_steps_legacy.log是中途取消的额外旧测试，narrow_map_compat.log含旧单效果测试编译失败，均未计入最终23组。
