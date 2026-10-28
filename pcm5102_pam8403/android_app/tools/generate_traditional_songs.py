"""Build the offline library from pinned, public-domain O'Neill ABC transcriptions.

Build-time only: music21==10.5.1. The APK needs neither Python nor network access.
Input: third_party/oneill/abc (selected sources); --select-from can select sources
from the pinned upstream checkout on initial import. Full editions including
notated repeats are preferred; wider/longer works may contribute a labelled excerpt
of complete bars. Each source tune appears at most once; no octave folding.
"""
import argparse
import copy
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
import shutil
import warnings

from music21 import converter

ROOT = Path(__file__).resolve().parents[1]
COMMIT = '23ff756d9b41fde178147ff2f8f736db340f5ddf'
SOURCE = f'https://github.com/folkies/oneill/blob/{COMMIT}/1850/abc/'
warnings.filterwarnings('ignore', module='music21')


def melody(path):
    text = path.read_text(encoding='utf-8-sig')
    title = re.search(r'^T:\s*(.+)', text, re.M).group(1).strip()
    if re.search(r'\b(?:2nd|3rd|4th|setting|version)\b', title, re.I):
        raise ValueError('alternative setting')
    parsed = converter.parse(text, format='abc')
    if len(parsed.parts) != 1:
        raise ValueError('not a single melody')
    original = parsed.parts[0]
    # A compact practice edition plays each written section once, taking its
    # first-pass ending. Never truncate a score to the event limit.
    part = copy.deepcopy(original)
    later_endings = []
    for bracket in part.spannerBundle.getByClass('RepeatBracket'):
        if 1 not in bracket.numberRange:
            later_endings.extend(bracket.getSpannedElements())
    for measure in sorted(set(later_endings), key=lambda m: m.offset, reverse=True):
        part.remove(measure, shiftOffsets=True)
    part = part.stripTies()
    notes, timed = [], []
    at = Fraction(0)
    for note in part.flatten().notesAndRests:
        if note.duration.isGrace:
            continue  # ornaments are explicitly omitted in the edition description
        if note.isChord:
            raise ValueError('polyphonic source')
        offset = Fraction(note.offset)
        if offset != at:
            raise ValueError('gap or overlap in source')
        length = Fraction(note.quarterLength)
        if length <= 0:
            raise ValueError('nonpositive duration')
        pitch = None if note.isRest else int(note.pitch.midi)
        notes.append((pitch, length))
        timed.append((at, pitch, length))
        at += length
    def fits(candidate):
        pitches = {n for n, _ in candidate if n is not None}
        return (12 <= len(candidate) <= 256 and 3 <= len(pitches) <= 12
                and max(pitches) - min(pitches) <= 12)
    repeats_expanded = False
    try:
        expanded = original.expandRepeats().stripTies()
        full_notes, full_at = [], Fraction(0)
        for note in expanded.flatten().notesAndRests:
            if note.duration.isGrace:
                continue
            if note.isChord or Fraction(note.offset) != full_at or note.quarterLength <= 0:
                raise ValueError('unsupported expanded source')
            length = Fraction(note.quarterLength)
            full_notes.append((None if note.isRest else int(note.pitch.midi), length))
            full_at += length
        if fits(full_notes):
            repeats_expanded = full_at > at
            notes, at = full_notes, full_at
    except Exception:
        pass  # retain the validated single-pass edition if repeats are ambiguous
    excerpt = False
    selection = '完整旋律，按原谱展开反复' if repeats_expanded else '全曲单遍，各段演奏一次并使用首遍结尾'
    if not fits(notes):
        measures = list(part.getElementsByClass('Measure'))
        found = False
        for count in (32, 24, 16, 12, 8, 4):
            for start in range(0, len(measures) - count + 1):
                begin = Fraction(measures[start].offset)
                end = (Fraction(measures[start + count].offset)
                       if start + count < len(measures) else at)
                window = [(t, n, q) for t, n, q in timed if begin <= t < end]
                # Never cut a tied/sustained note at an excerpt boundary.
                if not window or window[0][0] != begin or window[-1][0] + window[-1][2] != end:
                    continue
                candidate = [(n, q) for _, n, q in window]
                if fits(candidate):
                    notes, at = candidate, end - begin
                    selection = f'记谱第{start + 1}～{start + count}小节节选（含弱起小节，反复段只演奏一次）'
                    excerpt = found = True
                    break
            if found:
                break
        if not found:
            raise ValueError('no complete-bar edition fits range and capacity')
    pitches = {n for n, _ in notes if n is not None}
    low, high = min(pitches), max(pitches)
    # One constant transposition preserves every melodic interval.
    shift = 60 - low
    notes = [(None if n is None else n + shift, q) for n, q in notes]
    meter = re.search(r'^M:\s*(\d+/\d+)', text, re.M)
    if not meter:
        raise ValueError('unsupported meter')
    # Deduplicate pitch intervals and relative rhythm, independent of tempo/key.
    unit = min(q for _, q in notes)
    fingerprint = tuple((n, str(q / unit)) for n, q in notes)
    return dict(path=path, title=title, notes=notes, shift=shift,
                excerpt=excerpt, repeats_expanded=repeats_expanded, selection=selection,
                time=meter.group(1), beats=str(at), fingerprint=fingerprint,
                complexity=(float(1 / unit), len(pitches), len(notes)))


def emit(entries):
    lines = ['// Generated by tools/generate_traditional_songs.py; do not hand edit.',
             'package cn.fpga.score;', '', 'import java.util.List;', '',
             'final class TraditionalSongs {',
             '    static void appendTo(List<SongLibrary.Entry> out) {']
    manifest = []
    q = lambda s: json.dumps(s, ensure_ascii=False)
    for index, entry in enumerate(entries):
        tier = ['BRONZE', 'SILVER', 'GOLD'][index // 37]
        bpm = [84, 100, 112][index // 37]  # quarter-note BPM, including compound meters
        source = SOURCE + entry['path'].name
        title = entry['title'] + ('（节选）' if entry['excerpt'] else '')
        number = int(entry['path'].name.split('_')[0])
        edition = (f'O’Neill《Music of Ireland》(1903) 第{number}首；旋律练习版，{entry["selection"]}；'
                   f'省略装饰音；整体移调 {entry["shift"]:+d} 半音，保持音程与节奏；速度以四分音符为一拍。')
        at = Fraction(0)
        previous = 0
        pairs = []
        for pitch, length in entry['notes']:
            at += length
            # Round cumulative time, not each event, to avoid tempo drift.
            end = int(at * 60000 / bpm + Fraction(1, 2))
            duration = end - previous
            assert 1 <= duration <= 60000
            pairs.append(f'{-1 if pitch is None else pitch - 60}:{duration}')
            previous = end
        identifier = f'oneill-{number:04d}'
        lines += [f'        out.add(SongLibrary.traditional({q(identifier)}, {q(title)}, SongLibrary.Tier.{tier},',
                  f'            {q(entry["time"])}, {bpm}, {q(edition)},',
                  f'            {q(source)},', f'            {q(" ".join(pairs))}));']
        manifest.append(dict(id=identifier, title=title, tier=tier, meter=entry['time'],
                             bpm=bpm, quarter_beats=entry['beats'], shift=entry['shift'],
                             excerpt=entry['excerpt'], repeats_expanded=entry['repeats_expanded'], selection=entry['selection'],
                             events=len(pairs), duration_ms=previous, source=source,
                             abc_sha256=hashlib.sha256(entry['path'].read_bytes()).hexdigest()))
    lines += ['    }', '    private TraditionalSongs() {}', '}']
    output = ROOT / 'app/src/main/java/cn/fpga/score/TraditionalSongs.java'
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    (ROOT / 'third_party/oneill/catalogue.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(added=len(entries), tiers=dict(Counter(e['tier'] for e in manifest)),
                          full_single_pass=sum(not e['excerpt'] for e in manifest),
                          repeats_expanded=sum(e['repeats_expanded'] for e in manifest),
                          excerpts=sum(e['excerpt'] for e in manifest),
                          max_events=max(e['events'] for e in manifest)), ensure_ascii=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--select-from', type=Path)
    args = parser.parse_args()
    selected = ROOT / 'third_party/oneill/abc'
    directory = args.select_from or selected
    entries, fingerprints, titles = [], set(), set()
    skipped = Counter()
    for scanned, path in enumerate(sorted(directory.glob('*.abc')), 1):
        try:
            entry = melody(path)
            title_key = re.sub(r'[^a-z]', '', entry['title'].lower())
            if entry['fingerprint'] in fingerprints or title_key in titles:
                continue
            entries.append(entry)
            fingerprints.add(entry['fingerprint'])
            titles.add(title_key)
        except Exception as error:
            skipped[type(error).__name__] += 1
        if scanned % 100 == 0:
            print(f'Scanned {scanned}: selected {len(entries)}', flush=True)
    if args.select_from:
        entries.sort(key=lambda e: (e['excerpt'], e['path'].name))
        entries = entries[:111]
    if len(entries) != 111:
        raise ValueError(f'Expected 111 distinct single-pass melodies, got {len(entries)}; {skipped}')
    entries.sort(key=lambda e: (e['complexity'], e['path'].name))
    if args.select_from:
        selected.mkdir(parents=True, exist_ok=True)
        for entry in entries:
            target = selected / entry['path'].name
            shutil.copyfile(entry['path'], target)
            entry['path'] = target
    emit(entries)


if __name__ == '__main__':
    main()
