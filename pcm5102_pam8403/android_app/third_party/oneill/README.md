# O'Neill 1903 melody sources

111 selected melodies from Francis O'Neill and James O'Neill, *Music of Ireland:
Eighteen Hundred and Fifty Melodies*, Chicago: Lyon & Healy, 1903.

- Original ABC transcription project: [John Chambers and volunteer contributors](https://trillian.mit.edu/~jc/music/book/ONeills/_1850/www/index.html), 1996–1999.
- Source mirror: [folkies/oneill](https://github.com/folkies/oneill), pinned commit `23ff756d9b41fde178147ff2f8f736db340f5ddf`, `1850/abc/`.
- Historical edition: [Irish Traditional Music Archive catalogue](https://itmacatalogues.ie/Portal/Default/en-GB/RecordView/Index/80962), which identifies the 1903 edition as public domain.

`abc/` retains the selected upstream files unchanged, including transcriber credits.
`catalogue.json` records each source URL, original ABC SHA256, transposition,
meter, practice tempo, event count and duration. No audio, lyrics, scanned pages,
new harmonizations or modern arrangements are bundled.

The mechanical conversion uses music21 10.5.1 at build time only. It prefers
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

The APK contains the resulting numeric events in `TraditionalSongs.java`; neither
music21 nor the ABC interpreter runs on the phone or FPGA. The source files are
retained here for auditing and reproducible generation, rather than copied into
FPGA ROM.

Regenerate from this directory after installing the build dependency:

```powershell
python -m pip install music21==10.5.1
python tools/generate_traditional_songs.py
```

The original nine PrintableGarden melodies and their source links remain in
`SongLibrary.java`. The added tunes retain their English source titles; the
three library tiers are application practice categories.
