from work import *

labels = ['parallel_dispatch', 'map_serial', 'reply_parallel',
          'reply_place1', 'reply_fan12', 'reply_route1']
rows = []
for label in labels:
    audit_path = HERE / label / 'audit.json'
    result = json.loads(audit_path.read_text(encoding='utf-8'))
    rows.append({'label': label, 'status': result['status'],
                 'metrics': result['metrics'], 'delta_vs_baseline': result['delta_vs_baseline'],
                 'unrouted_nets': result['unrouted_nets'], 'timing': result['timing'],
                 'audit_sha256': sha(audit_path),
                 'selected': label == 'reply_place1'})
integration = json.loads((HERE / 'integration.json').read_text(encoding='utf-8'))
verification = json.loads((HERE / 'reply_place1/verification.json').read_text(encoding='utf-8'))
assert verification['all_passed'] and len(verification['checks']) == 17
assert integration['selected'] == 'reply_place1'
save(HERE / 'results.json', {'selected': 'reply_place1', 'trials': rows,
                            'bitstream_sha256': integration['production_bitstream_sha256'],
                            'source_verification_count': len(integration['production_inputs']),
                            'functional_test_count': len(verification['checks'])})
note = '''
## 全部策略的结束状态

| 候选 | 资源/物理结果 | 采用 |
|---|---|---|
| parallel_dispatch | 放置失败，26 LUT 等价单元未放入 | 否 |
| map_serial | 完整通过，但 CLS +13 | 否 |
| reply_parallel：place2/route0/fan23 | CLS -50，9 个 setup 端点违例，原始 WNS -1.586ns | 否 |
| reply_place1：place1/route0/fan23 | CLS -83，完整布通，setup/hold 端点违例0/0，WNS +0.081/+0.153ns | 是 |
| reply_fan12：place2/route0/fan12 | 仍有相同9个 setup 端点违例，原始 WNS -1.586ns | 否 |
| reply_route1：place2/route1/fan23 | 3925 条网络未布通 | 否 |

各候选独立差值不相加；未布通和时序失败版本均未交付。
接入过程中遇到默认生成 .bin/.fs 的 Windows 只读属性，确认回退副本完整后仅清除指定目标的只读位并续传。
源码、构建脚本及24项输出全部逐项哈希核对完成；未修改文件ACL或任何板上存储。
'''
path = HERE / 'README.md'
text = path.read_text(encoding='utf-8')
if '## 全部策略的结束状态' not in text:
    path.write_text(text + note, encoding='utf-8')
print('Collected six complete trial records; selected place1 and verified 17 checks')
