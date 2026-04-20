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

## 2. Decision Matrix: Analysis Depth

Agents should choose the analysis mode based on the user's urgency and required precision.

| Mode | Use Case | Latency |
| :--- | :--- | :--- |
| **`.summary`** | Quick metadata check, BPM, basic Key. | < 1s |
| **`.balanced`** | Standard production work, source separation. | 2-5s |
| **`.forensic`** | Absolute truth verification, AES17 audit. | 10s+ |

---

## 3. Handling Output (The Agent's Role)

AudioIntelligence generates a structured result. As an agent, your role is to:
1.  **Orchestrate**: Call the `AudioIntelligence.analyze()` method with the correct flags.
2.  **Verify**: Check the `report.reportPath` to ensure the `.dna.md` file was successfully written.
3.  **Present**: Read the **Hidden JSON block** from the report (see [Report Specification](REPORT_SPECIFICATION.md)) to populate your own UI widgets or generate a custom narrative response.

---

## 4. Anti-Patterns for AI Agents

> [!CAUTION]
> - **Don't Hallucinate Specs**: If the user asks for "THD+N", check the `science` lane first. If it wasn't requested in the `features` set, don't invent a value.
> - **Don't ignore the Offset**: Analysis is fragment-based. Ensure you are looking at the global aggregation in the final report.
> - **Safety First**: Always use the "Copy-on-Process" pattern (cloning the original file to a temp directory) to prevent accidental mutation of user assets.

---
*Generated for: Professional AI Integrations — v7.1 Aligned*
