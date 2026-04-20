# 📑 Report Specification (.dna.md) — Phase 7 Aligned

The `.dna.md` file is the primary forensic output of the **AudioIntelligence Infinity Engine**. It is designed to be both human-readable for professional audits and machine-readable for AI agents and automated verification pipelines.

---

## 1. File Structure Overview

The report consists of 12 standard sections, followed by an **Inferred Context** verdict and a **Hidden JSON Metadata** block.

| Section | Content | Purpose |
| :--- | :--- | :--- |
| **1. Integrity Audit** | Hardware & Software status | Verify forensic chain of custody |
| **2. Mastering DNA** | LUFS, True Peak, Phase | EBU R128 compliance check |
| **3. Rhythmic DNA** | BPM, Confidence, Consistency | Temporal analysis |
| **4. Tonal DNA** | Key, Scale, Chroma Profile | Harmonic mapping |
| **5. Spectral DNA** | Centroid, Flatness, ZCR | Timbral characterization |
| **6. Source Separation** | Harmonic/Percussive ratios | Signal decomposition |
| **7. Forensic Analysis** | Bit-depth, Entropy, Cutoff | Provenance and truth verification |
| **8. Structural Segmentation**| Segment boundaries (Intro, Verse) | Song structure mapping |
| **9. Engine Registry** | 26-engine checklist | Audit transparency |
| **10. Laboratory Science** | AES17, IMD, SNR | Pure scientific metrics |
| **11. Instrument DNA** | Neural predictions | Instrument identification |
| **12. Infinity Data Dump** | **Hidden JSON Block** | Machine-readable integration |

---

## 2. The Hidden JSON Metadata Block

To facilitate seamless integration with AI agents (like EliteAgent), every report contains a structural JSON dump at the end of the file.

### Location
The JSON block is located at the bottom of the file, wrapped in a `<details>` tag for cleanliness in standard Markdown viewers.

### AI Parsing Instruction
AI Agents should look for the block starting with `## 📊 12. Infinity Data Dump` and parse the content inside the ` ```json ` fences.

### Schema
The JSON conforms to the `MusicDNAAnalysis` Swift model. Key fields include:
- `mastering`: Object containing `integratedLUFS`, `truePeak`, etc.
- `forensic`: Object containing `isUpsampled`, `effectiveBits`, `codecCutoffHz`.
- `musicology`: Object containing `ursatz`, `cadences`, `motifs`.

---

## 3. Integration Patterns for Agents

When an agent reads a `.dna.md` file, it should follow this protocol:

1.  **Verify Integrity**: Check Section 1 or the JSON `forensic.isVerified` field.
2.  **Extract Summary**: Use the top-level human-readable sections for a quick gist.
3.  **Deep Dive**: Parse the JSON block for specific mathematical thresholds (e.g., "If entropy < 0.6, trigger FRAUD alert").

---

## 4. Standardized File Naming
Reports should always use the `.dna.md` suffix (e.g., `SongName.dna.md`) to distinguish them from standard documentation or plain text reports.

---
*Last Updated: 2026-04-20 — AudioIntelligence V7.1*
