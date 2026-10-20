"""Read-only checks. Never connects to a programmer or erases any storage."""
import argparse
import binascii
import hashlib
import json
import re
from pathlib import Path

FLASH_BYTES = 0x800000
TAKE_BASE = 0x7FC000
SLOT_BYTES = 8192
MAX_EVENTS = 1024


def inspect_slot(data):
    assert len(data) == SLOT_BYTES
    if data == b'\xff' * SLOT_BYTES:
        return {'kind': 'blank', 'erasable_by_recorder': True, 'committed': False}
    count_flags = int.from_bytes(data[6:8], 'little')
    count = count_flags & 0x7fff
    duration = int.from_bytes(data[8:11], 'little')
    shape = data[:4] == b'FPT1' and count <= MAX_EVENTS and (
        count != 0 or (duration == 0 and not count_flags & 0x8000))
    expected = int.from_bytes(data[11:15], 'little')
    actual = binascii.crc32(data[:11] + data[256:256 + 6 * count]) & 0xffffffff
    integrity = shape and expected == actual
    padding = data[16:256] + data[256 + 6 * count:]
    padding_blank = all(v == 255 for v in padding)
    owned = integrity and padding_blank and data[15] in (0, 255)
    return {'kind': 'recorder' if owned else 'unknown_or_incomplete',
            'erasable_by_recorder': owned, 'committed': integrity and data[15] == 0,
            'generation': int.from_bytes(data[4:6], 'little'), 'events': count,
            'duration_ms': duration, 'full': bool(count_flags & 0x8000),
            'crc32_stored': f'{expected:08X}', 'crc32_computed': f'{actual:08X}',
            'padding_blank': padding_blank}


def inspect_bitstream(path):
    text = path.read_text(encoding='ascii')
    assert '//Device: GW5A-25' in text, 'Wrong target device'
    bits = 0
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('//'):
            continue
        assert re.fullmatch('[01]+', line), 'Unknown bitstream encoding'
        bits += len(line)
    assert bits and bits % 8 == 0, 'Invalid payload length'
    payload = bits // 8
    assert payload < TAKE_BASE, 'Configuration image overlaps event partition'
    return {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'configuration_base': 0, 'configuration_payload_bytes': payload,
            'take_base': f'{TAKE_BASE:06X}', 'configuration_overlap': False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bitstream', type=Path, required=True)
    p.add_argument('--config', type=Path)
    p.add_argument('--dump', type=Path, help='Optional complete 8MiB raw Flash readback')
    args = p.parse_args()
    result = inspect_bitstream(args.bitstream)
    if args.config:
        config = json.loads(args.config.read_text(encoding='utf-8-sig'))
        assert config.get('MULTIBOOT_MODE') == 'Single', 'Unverified multi-boot layout'
        assert int(config.get('MULTIBOOT_SPI_FLASH_ADDRESS', '0'), 16) == 0, 'Nonzero boot base'
        result['single_image_project'] = True
    result['physical_jedec_verified'] = False
    if args.dump:
        dump = args.dump.read_bytes()
        assert len(dump) == FLASH_BYTES, 'Readback must be a complete 8MiB raw image'
        result['readback_sha256'] = hashlib.sha256(dump).hexdigest()
        result['slots'] = [inspect_slot(dump[TAKE_BASE + n * SLOT_BYTES:TAKE_BASE + (n + 1) * SLOT_BYTES])
                           for n in range(2)]
    else:
        result['existing_flash_contents_verified'] = False
        result['status'] = 'IMAGE_RANGE_CHECKED; PHYSICAL_ID_AND_SLOT_OWNERSHIP_REQUIRE_RUNTIME_CHECK'
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
