# 📑 Report Specification — `AudioReport`

`analyze()` returns a single typed value, **`AudioReport`**. This *is* the product — a
markdown / JSON / PDF document is merely one *rendering* of it. The library produces data and
**writes no files**; the consuming application decides how to persist or present it.

The schema is deliberately split into two layers so a consumer can never confuse the two:

- **Measurements** — objective, deterministic, standards-traceable numbers. Each is a
  `Measured<T>` carrying its `unit`, the `standard` it conforms to, and whether it was
  `validated` against a reference implementation.
- **Estimations** — statistical interpretations that are *never* 100% certain. Each is an
  `Estimated<T>` carrying a `confidence` (0…1), the `method` that produced it, and optional
  ranked `alternatives`.

---

## 1. Top-level structure

```
AudioReport
├── id                UUID
├── schemaVersion     String   ("1.0.0")
├── libraryVersion    String
├── analyzedAt        Date
├── metadata          ReportMetadata   (file, duration, sampleRate, channels, encoder)
├── measurements      Measurements     (certifiable layer)
├── estimations       Estimations      (statistical layer)
└── features          LowLevelFeatures?  (heavy series; optional in serialization)
```

`schemaVersion` is a semantic version of the schema itself. New fields (e.g. the upcoming
instrument/genre layer) are added *additively* and bump the minor version, so existing
consumers keep working.

---

## 2. The wrapper types

```swift
struct Measured<Value: Codable & Sendable> {
    let value: Value
    let unit: MetricUnit            // .lufs .dBTP .dB .lu .percent .hertz .bits .ratio …
    let standard: MetricStandard?   // .ebuR128 .ituBS1770 .aes17 .itu468 .smpte .librosaParity
    let validated: Bool             // checked against a reference (ffmpeg/librosa/standard signal)
}

struct Estimated<Value: Codable & Sendable> {
    let value: Value
    let confidence: Double          // 0…1 — a relative score, not a probability guarantee
    let method: String              // e.g. "Krumhansl-Schmuckler on high-res STFT chroma"
    let alternatives: [Alternative<Value>]?   // ranked runner-ups (relative key, ½/2× tempo, …)
}
```

A downstream integrator branches on `.validated` / `.standard` for measurements and thresholds
`.confidence` for estimations — instead of trusting a hardcoded badge.

---

## 3. `measurements` (certifiable)

| Group | Fields | Unit · Standard |
| :--- | :--- | :--- |
| `loudness` | `integrated`, `shortTermMax`, `momentaryMax` | LUFS · EBU R128 |
| | `range` | LU · EBU Tech 3342 |
| | `truePeak` | dBTP · ITU-R BS.1770 |
| `fidelity` | `thdPlusN` | % · AES17 |
| | `imd` | % · SMPTE |
| | `snr`, `noiseFloor468` | dB · (ITU-R 468 for noise floor) |
| `stereo` | `phaseCorrelation`, `width`, `sideEnergyPercent`, `midSideBalance`, `balanceLR` | ratio / dimensionless |
| `forensic` | `sourceBitDepth` (declared), `effectiveBits` (measured), `isUpsampled` (Bool), `codecCutoff` (Hz), `clippingEvents`, `entropyScore` | — |
| `spectral` | `centroid`, `rolloff`, `bandwidth` (Hz), `flatness`, `flux`, `zeroCrossingRate`, `rmsMean`, `rmsMax` | librosa parity |
| `separation` | `harmonicRatio`, `percussiveRatio` | ratio (HPSS) |

`isUpsampled` ("fake hi-res") is `true` only when the declared `sourceBitDepth` exceeds the
**measured** `effectiveBits` — i.e. the container claims more bits than the signal actually
uses. (It is **not** keyed on entropy; see [Forensics.md](Forensics.md).)

`fidelity.thdPlusN` and `fidelity.imd` are **test-tone-only** lab metrics (AES17 / SMPTE need a
997 Hz / 7 kHz stimulus). On real-world musical material no tone is present, so they report `0`
with **`validated: false`** — read this as "not measurable on this signal," not as a certified
`0%`. Always branch on `.validated` before surfacing them.

---

## 4. `estimations` (statistical)

| Field | Type | Notes |
| :--- | :--- | :--- |
| `tempo` | `Estimated<Double>` | BPM |
| `key` | `Estimated<String>` | e.g. `"A minor"` |
| `timeSignature` | `Estimated<String>` | e.g. `"4/4"` |
| `pitch` | `PitchMetrics` | f0 statistics |
| `structure` | `[MusicSegment]` | section boundaries |
| `instruments` | `[Estimated<String>]?` | per-instrument; `nil` until the instrument layer ships |
| `musicology` | `MusicologyReport` | interpretive: chords, cadences, modulations, motifs, meter |

`musicology` is the most speculative layer; treat it as analytical assistance, not ground
truth.

---

## 5. `features` (heavy, optional in serialization)

Low-level series — `chromaProfile`, `mfcc`, `spectralContrast`, `tonnetz`, `tempogramCyclic`,
`nmfComponentEnergy`, `viterbiPitchPath`, `waveformPeaks`, `magnitudeSpectrogram`.

These are **always present in memory** (a Swift consumer pays nothing — no serialization), but
can be **excluded from a serialized export** to keep files small:

```swift
let full = try report.jsonData()                       // everything
let lean = try report.jsonData(includingFeatures: false) // drops the heavy series
```

---

## 6. Transport & rendering

```swift
// Codable-first — both formats are one line:
let json  = try report.jsonData(prettyPrinted: true)   // universal (any language/runtime)
let plist = try report.plistData()                     // Apple-native binary (compact, fast)

// Decode back:
let a = try AudioReport.decoded(fromJSON: json)
let b = try AudioReport.decoded(fromPlist: plist)

// Optional reference document (pure function; analyze() does NOT call it):
let markdown = MarkdownRenderer.render(report)
```

Persisting is the caller's responsibility — write `json` / `plist` / `markdown` wherever you
like. The library never touches the filesystem.

---

## 7. Notes for AI agents / automated consumers

1. **Read measurements as facts, estimations as hypotheses.** Gate on
   `measurements.*.validated` and `estimations.*.confidence`; never assume an estimate is
   correct.
2. **Pin `schemaVersion`.** It is the contract; new fields are additive.
3. **Prefer JSON for cross-language pipelines**, binary plist for Apple-to-Apple.

---
*Schema 1.0.0 — AudioIntelligence 8.2.1*
