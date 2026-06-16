# 🤖 AI Integration Guide: The Agent Intelligence Bridge

This guide is designed for **AI Agents** (like Antigravity, EliteAgent, or custom LLM-based tools) and developers who need to understand how to programmatically leverage **AudioIntelligence** to solve high-fildelity audio tasks.

---

## 1. The Intent-to-Engine Mapping

When an AI agent receives a user prompt, it should map the "Intent" to the corresponding **Analysis Lane** or specific **Engine**.

| User Intent / Keyword | Analysis Lane / Engine | Recommended Features |
| :--- | :--- | :--- |
| "Is this audio authentic?" | `forensic` | `[.forensic]` |
| "What is the BPM / tempo?" | `rhythm` | `[.rhythm]` |
| "Analyze the chord progression"| `tonal` | `[.harmonic, .spectral]` |
| "Separate vocals/drums" | `hpss` | `[.separation]` |
| "Meet EBU R128 standards" | `mastering` | `[.mastering]` |
| "Detect instruments" | `instruments` | `[.semantic]` |
| "Spectral density / quality" | `spectral` | `[.spectral]` |
| "Full Forensic Audit" | `audit` | `[.forensic, .mastering, .spectral, .harmonic]` |

---

## 2. Scoping the analysis with `features`

`analyze(url:features:)` takes a `Set<AudioFeature>`; pass only the domains you need to keep
latency down. Agents should map intent → the minimal feature set:

| Intent | `features` |
| :--- | :--- |
| Quick BPM / key check | `[.rhythm, .harmonic]` |
| Loudness / mastering check | `[.mastering]` |
| Forensic / authenticity audit | `[.forensic, .mastering, .spectral]` |
| Full analysis (default) | omit the argument → all features |

---

## 3. Handling Output (The Agent's Role)

`analyze()` returns a typed **`AudioReport`** — there is no file on disk to look for, and no
hidden JSON block to scrape. Your role:

1.  **Orchestrate**: Call `AudioIntelligence.analyze(url:features:)` with the minimal feature set.
2.  **Read the typed value directly**, respecting the two layers:
    ```swift
    let report = try await ai.analyze(url: url, features: [.mastering, .rhythm])

    // Measurement → treat as fact (and you can check it):
    let lufs = report.measurements.loudness.integrated
    if lufs.validated { use(lufs.value, lufs.standard) }   // EBU R128

    // Estimation → treat as a hypothesis, threshold the confidence:
    let tempo = report.estimations.tempo
    if tempo.confidence > 0.7 { suggest(tempo.value) }
    ```
3.  **Serialize if you need to hand data off**: `report.jsonData()` (universal) or
    `report.plistData()` (Apple-native). Persisting is *your* choice — the library writes nothing.

See the [Report Specification](REPORT_SPECIFICATION.md) for the full schema.

---

## 4. Anti-Patterns for AI Agents

> [!CAUTION]
> - **Don't present estimates as facts.** Gate on `measurements.*.validated` and
>   `estimations.*.confidence`. A key/tempo/instrument estimate can be wrong.
> - **Don't request features you won't use.** If the user didn't ask for THD+N, don't include
>   `.forensic`/`.mastering` just to read a number you'll ignore.
> - **Don't assume capabilities we don't have.** The instrument layer is a placeholder today;
>   `estimations.instruments` is best-effort and may be `nil`.
> - **Safety First**: Use a "copy-on-process" pattern (clone the source to a temp directory)
>   so analysis never risks mutating the user's original asset.

---
*Generated for: Professional AI Integrations — AudioIntelligence 8.2.0*
