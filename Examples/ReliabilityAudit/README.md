# ReliabilityAudit

A single, repeatable pass over every engine that has a real, independently-sourced ground-truth
dataset, producing a dated "reliability scorecard" — instead of scattered ad-hoc test runs whose
results live only in a terminal scrollback.

Every row is either **measured** against real data, or explicitly reported **`not_available`**
with the reason. Nothing is silently skipped, and nothing is guessed.

## Why this exists, and not just `swift test`

Some of these batteries run over hundreds or thousands of real audio files (GiantSteps tempo:
~30s/track; IRMAS: 6,718 files; OpenMIC-2018: 20,000 clips) — genuinely too slow for the normal
`swift test` inner loop. This is a manually-run tool (or a release-gate step), matching the
existing `InfinityAudit` / `SQAMAuditTool` pattern in `Examples/`.

## Running it

```bash
swift run -c release ReliabilityAudit
```

By default each battery runs on a small, evenly-spaced sample (not just the first N — a
deterministic stride across the full set) so a run finishes in a few minutes. Size any battery
with an `RA_*_LIMIT` environment variable; `0` means "use the full dataset":

```bash
RA_TEMPO_LIMIT=0 RA_KEY_LIMIT=0 RA_IRMAS_PER_CLASS=0 RA_OPENMIC_LIMIT=0 RA_PITCH_LIMIT=0 \
  swift run -c release ReliabilityAudit          # full, "official" run — takes hours
```

| Env var | Default | Battery |
| :-- | :-- | :-- |
| `RA_TEMPO_LIMIT` | 15 | GiantSteps tempo (of 43 MIREX-BPM tracks) |
| `RA_KEY_LIMIT` | 15 | GiantSteps key (of 599 MIREX-key tracks) |
| `RA_IRMAS_PER_CLASS` | 15 | IRMAS instrument (per each of 11 classes) |
| `RA_OPENMIC_LIMIT` | 60 | OpenMIC-2018 instrument (of clips with ≥1 confirmed-positive label) |
| `RA_PITCH_LIMIT` | 12 | MDB-stem-synth pitch/f0 (of 230 stems) |

## What each battery measures, and against what

| Task | Metric | Ground truth | Why this dataset |
| :-- | :-- | :-- | :-- |
| `tempo_acc1` / `tempo_acc2` | MIREX Acc1 (±4%) / Acc2 (±4%, octave-tolerant) | GiantSteps MIREX-annotated BPM | Real EDM, human-corrected annotations |
| `key_exact` / `key_mirex_weighted` | Exact key match / MIREX-weighted (fifth=0.5, relative=0.3, parallel=0.2) | GiantSteps MIREX-annotated key | Same dataset, same annotation provenance |
| `instrument_irmas` | `primaryLabel` in an acceptable coarse-class set | IRMAS single-predominant-instrument label | Single-label ground truth matches `InstrumentEngine.primaryLabel`'s own single-label design — a fairer test than a multi-label set |
| `instrument_openmic` | same | OpenMIC-2018 aggregated relevance ≥ 0.5 → positive (the dataset paper's own majority-vote threshold, confirmed against Fig. 5 of the original ISMIR 2018 paper) | Broader instrument vocabulary (20 classes), multi-label, different bias than IRMAS |
| `pitch_f0` | Raw Pitch Accuracy — estimate within 50 cents of true f0, standard MIR tolerance | MDB-stem-synth: f0 known from **re-synthesis**, not a human/algorithmic estimate | The strongest kind of pitch ground truth available — it isn't an estimate at all |
| `chord` | — | *(gap — see below)* | |
| `structure` | — | *(gap — see below)* | |

### Coarse-class mapping (11/20 fine classes → 6 `InstrumentEngine` classes)

`InstrumentEngine` only has 6 classes (Piano/Keyboard, Bass, Brass/Trumpet, Vocals/Chorus,
Drums/Percussion, Strings/Synth) and no woodwind category — `irmasToCoarse` / `openmicToCoarse`
in `main.swift` map each source dataset's finer classes onto an *acceptable* coarse-class set
(several fine classes map to more than one acceptable coarse class where there's no exact
match, e.g. clarinet/flute), the same "acceptable class list" approach the existing SQAM
baseline test already uses. This is a real limitation of the mapping, not of the measurement —
tightening it would require adding coarse classes to `InstrumentEngine` itself.

### Known gaps — not swept under the rug

- **Chord** (`TraditionalTheoryEngine`): the two standard chord-annotation datasets
  (Isophonics/Beatles, McGill Billboard) distribute **annotations only** — the source audio is
  under copyright and neither project can redistribute it. There is currently no legally
  obtainable audio to pair with these annotations for an end-to-end test of our own
  STFT→chroma→CQT→chord pipeline.
- **Structure** (`StructureEngine`): SALAMI's annotations are open, but its audio spans several
  original sources (Internet Archive Live Music Archive, RWC, Codaich, Isophonics) with no
  single bulk archive — matching each track ID to a downloadable file is a separate, nontrivial
  effort that hasn't been done yet.

Both report as `not_available` with the reason above, rather than being silently omitted from
the scorecard.

## Output

- Prints a table to stdout.
- Writes `reliability_report.json` (this run's full result, machine-readable) — git-ignored, a
  regenerated snapshot, not source.
- Appends one line to `history.jsonl` — **intentionally tracked in git**, one JSON line per run,
  so accuracy over time/commits is a diffable, versioned trend. Commit it after a real
  (non-`RA_*_LIMIT`-truncated, or deliberately-sized) run you want on the record.
