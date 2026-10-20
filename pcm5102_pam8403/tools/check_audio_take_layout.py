"""Offline audio partition/CRC checks; never accesses or programs hardware."""
import argparse
import binascii
import hashlib
import json
import re
from pathlib import Path

BASE, END, SLOT = 0x100000, 0x7FC000, 0x37E000
MAX_SAMPLES = 1464843
FOOTPRINT = 0x2CD000


def inspect_slot(data, divisor=1024, maximum=MAX_SAMPLES):
    if data == b'\xff' * len(data):
        return {'kind': 'blank', 'erasable': True, 'committed': False}
    count = int.from_bytes(data[8:12], 'little')
    pcm_crc = int.from_bytes(data[12:16], 'little')
    shape = (data[:6] == b'FAT1\x01\x00' and 0 < count <= maximum and
             int.from_bytes(data[16:20], 'little') == 50000000 and
             int.from_bytes(data[20:22], 'little') == divisor and data[22:24] == b'\x10\x01')
    header_ok = shape and binascii.crc32(data[:24]) == int.from_bytes(data[24:28], 'little')
    end = 4096 + 2 * count
    actual_crc = binascii.crc32(data[4096:end])
    padding_ok = data[28:32] + data[33:4096] + data[end:] == b'\xff' * (len(data) - 29 - count * 2)
    owned = header_ok and end <= len(data) and padding_ok and actual_crc == pcm_crc and data[32] == 0
    return {'kind': 'committed_audio' if owned else 'unknown_or_incomplete', 'erasable': owned,
            'committed': owned, 'samples': count, 'generation': int.from_bytes(data[6:8], 'little'),
            'header_crc_ok': header_ok, 'pcm_crc_stored': f'{pcm_crc:08X}',
            'pcm_crc_computed': f'{actual_crc:08X}', 'padding_blank': padding_ok}


def inspect_image(path):
    bits = 0
    for line in path.read_text(encoding='ascii').splitlines():
        line = line.strip()
        if not line or line.startswith('//'):
            continue
        assert re.fullmatch('[01]+', line), 'Unknown FS encoding'
        bits += len(line)
    assert bits and bits % 8 == 0
    payload = bits // 8
    assert payload < BASE, 'Configuration overlaps the audio partition'
    return {'configuration_payload_bytes': payload, 'reserved_configuration_bytes': BASE,
            'configuration_overlap': False, 'audio_slots': ['100000', '47E000'],
            'slot_bytes': SLOT, 'erase_footprint_bytes': FOOTPRINT, 'event_partition': ['7FC000', '800000'],
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'physical_jedec_verified': False, 'physical_flash_readback_verified': False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bitstream', required=True, type=Path)
    p.add_argument('--dump', type=Path, help='Optional complete 8MiB raw Flash readback')
    p.add_argument('--fixture', type=Path, help='RTL unit-test slot readmemh, 8KiB')
    args = p.parse_args()
    result = inspect_image(args.bitstream)
    if args.dump:
        data = args.dump.read_bytes()
        assert len(data) == 0x800000, 'Expected a complete 8MiB raw image'
        result['dump_sha256'] = hashlib.sha256(data).hexdigest()
        result['slots'] = [inspect_slot(data[b:b + FOOTPRINT]) for b in [BASE, BASE + SLOT]]
        result['physical_flash_readback_verified'] = True
    if args.fixture:
        words = [v for line in args.fixture.read_text().splitlines() if not line.startswith('//')
                 for v in line.split() if not v.startswith('@')]
        data = bytes(int(v, 16) for v in words)
        result['rtl_fixture'] = inspect_slot(data, divisor=65535, maximum=1525)
        assert result['rtl_fixture']['committed'] and result['rtl_fixture']['samples'] == 1525
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
