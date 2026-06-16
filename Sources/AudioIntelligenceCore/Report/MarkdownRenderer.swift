import Foundation

// =============================================================================
// MarkdownRenderer — an optional, pure rendering of an AudioReport.
//
// This is a convenience/reference renderer, not part of `analyze()`. A consuming
// app can ignore it entirely and render the typed `AudioReport` however it
// likes. It deliberately does NOT fabricate verdicts: measurements are presented
// with their unit/standard/validation state; estimations are presented with
// their confidence and method, under a clearly separate heading.
// =============================================================================

public enum MarkdownRenderer {

    public static func render(_ report: AudioReport) -> String {
        var s = ""
        s += header(report)
        s += metadataSection(report.metadata)
        s += measurementsSection(report.measurements)
        s += estimationsSection(report.estimations)
        s += footer(report)
        return s
    }

    // MARK: - Formatting helpers

    private static func num(_ v: Double, _ digits: Int = 2) -> String {
        if v.isNaN { return "n/a" }
        if v.isInfinite { return v > 0 ? "+∞" : "-∞" }
        return String(format: "%.\(digits)f", v)
    }

    private static func pct(_ ratio: Double) -> String { num(ratio * 100, 1) + "%" }

    /// Renders a `Measured` as `value unit` plus its standard and validation tag.
    private static func cell(_ m: Measured<Double>, _ digits: Int = 2) -> String {
        var t = "\(num(m.value, digits)) \(m.unit.rawValue)".trimmingCharacters(in: .whitespaces)
        if let std = m.standard { t += " · \(std.rawValue)" }
        t += m.validated ? " · ✅ validated" : " · ⚠️ unvalidated"
        return t
    }

    private static func cellInt(_ m: Measured<Int>) -> String {
        var t = "\(m.value) \(m.unit.rawValue)".trimmingCharacters(in: .whitespaces)
        t += m.validated ? " · ✅ validated" : " · ⚠️ unvalidated"
        return t
    }

    // MARK: - Sections

    private static func header(_ r: AudioReport) -> String {
        """
        # Audio Analysis Report — \(r.metadata.fileName)

        > Schema \(r.schemaVersion) · Library \(r.libraryVersion) · \(r.analyzedAt.ISO8601Format())

        This report has two layers. **Measurements** are objective, standards-traceable
        figures (validated against reference implementations). **Estimations** are
        statistical interpretations with a confidence — treat them as estimates, not facts.


        """
    }

    private static func metadataSection(_ m: ReportMetadata) -> String {
        """
        ## File

        | Field | Value |
        | :--- | :--- |
        | Duration | \(num(m.durationSeconds, 1)) s |
        | Sample rate | \(Int(m.sampleRate)) Hz |
        | Channels | \(m.channelCount) |
        | Encoder | \(m.encoder ?? "—") |


        """
    }

    private static func measurementsSection(_ m: Measurements) -> String {
        var s = "## Measurements (objective)\n\n"

        s += "### Loudness — EBU R128 / ITU-R BS.1770\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Integrated | \(cell(m.loudness.integrated, 1)) |\n"
        s += "| Short-term max | \(cell(m.loudness.shortTermMax, 1)) |\n"
        s += "| Momentary max | \(cell(m.loudness.momentaryMax, 1)) |\n"
        s += "| Loudness range (LRA) | \(cell(m.loudness.range, 1)) |\n"
        s += "| True peak | \(cell(m.loudness.truePeak, 1)) |\n\n"

        s += "### Fidelity — AES17 / SMPTE / ITU-R 468\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| THD+N | \(cell(m.fidelity.thdPlusN, 4)) |\n"
        s += "| IMD (SMPTE) | \(cell(m.fidelity.imd, 4)) |\n"
        s += "| SNR | \(cell(m.fidelity.snr, 1)) |\n"
        s += "| Noise floor (ITU-R 468) | \(cell(m.fidelity.noiseFloor468, 1)) |\n\n"

        s += "### Stereo field\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Phase correlation | \(cell(m.stereo.phaseCorrelation, 3)) |\n"
        s += "| Width | \(cell(m.stereo.width, 3)) |\n"
        s += "| Side energy | \(cell(m.stereo.sideEnergyPercent, 1)) |\n"
        s += "| Mid/Side balance | \(cell(m.stereo.midSideBalance, 3)) |\n"
        s += "| L/R balance | \(cell(m.stereo.balanceLR, 3)) |\n\n"

        s += "### Forensic integrity\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Source bit depth | \(cellInt(m.forensic.sourceBitDepth)) |\n"
        s += "| Effective bits | \(cellInt(m.forensic.effectiveBits)) |\n"
        s += "| Upsampled (fake hi-res) | \(m.forensic.isUpsampled ? "⚠️ yes" : "no") |\n"
        s += "| Codec cutoff | \(cell(m.forensic.codecCutoff, 0)) |\n"
        s += "| Clipping events | \(cellInt(m.forensic.clippingEvents)) |\n"
        s += "| Entropy score | \(cell(m.forensic.entropyScore, 3)) |\n\n"

        s += "### Spectral descriptors — librosa parity\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Centroid | \(cell(m.spectral.centroid, 1)) |\n"
        s += "| Rolloff | \(cell(m.spectral.rolloff, 1)) |\n"
        s += "| Bandwidth | \(cell(m.spectral.bandwidth, 1)) |\n"
        s += "| Flatness | \(cell(m.spectral.flatness, 4)) |\n"
        s += "| Flux | \(cell(m.spectral.flux, 4)) |\n"
        s += "| Zero-crossing rate | \(cell(m.spectral.zeroCrossingRate, 4)) |\n"
        s += "| RMS (mean) | \(cell(m.spectral.rmsMean, 4)) |\n\n"

        s += "### Source separation (HPSS)\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Harmonic ratio | \(cell(m.separation.harmonicRatio, 3)) |\n"
        s += "| Percussive ratio | \(cell(m.separation.percussiveRatio, 3)) |\n\n"

        return s
    }

    private static func estimationsSection(_ e: Estimations) -> String {
        var s = "## Estimations (statistical — not certainties)\n\n"

        s += "| Estimate | Value | Confidence | Method |\n| :--- | :--- | :--- | :--- |\n"
        s += "| Tempo | \(num(e.tempo.value, 1)) BPM | \(pct(e.tempo.confidence)) | \(e.tempo.method) |\n"
        s += "| Key | \(e.key.value) | \(pct(e.key.confidence)) | \(e.key.method) |\n"
        s += "| Time signature | \(e.timeSignature.value) | \(pct(e.timeSignature.confidence)) | \(e.timeSignature.method) |\n\n"

        s += "### Pitch (f0)\n\n"
        s += "| Metric | Value |\n| :--- | :--- |\n"
        s += "| Mean f0 | \(num(Double(e.pitch.meanF0), 1)) Hz |\n"
        s += "| Median f0 | \(num(Double(e.pitch.medianF0), 1)) Hz |\n"
        s += "| Voiced ratio | \(pct(Double(e.pitch.voicedRatio))) |\n\n"

        if !e.structure.isEmpty {
            s += "### Structure\n\n"
            s += "| # | Start | End | Label |\n| :-- | :--- | :--- | :--- |\n"
            for seg in e.structure {
                s += "| \(seg.id) | \(num(seg.start, 1))s | \(num(seg.end, 1))s | \(seg.label) |\n"
            }
            s += "\n"
        }

        if let instruments = e.instruments, !instruments.isEmpty {
            s += "### Instruments\n\n"
            s += "| Instrument | Confidence | Basis |\n| :--- | :--- | :--- |\n"
            for inst in instruments {
                s += "| \(inst.value) | \(pct(inst.confidence)) | \(inst.method) |\n"
            }
            s += "\n"
        }

        s += musicologySection(e.musicology)
        return s
    }

    private static func musicologySection(_ m: MusicologyReport) -> String {
        var s = "### Musicology (interpretive)\n\n"
        s += "- Fundamental note: **\(m.fundamentalNote)**\n"
        s += "- Meter: \(m.meter.timeSignature) (\(m.meter.meterType))\n"
        s += "- Counterpoint species: \(m.counterpointSpecies)\n\n"

        if !m.chords.isEmpty {
            s += "| Frame | Chord | Function |\n| :--- | :--- | :--- |\n"
            for c in m.chords.prefix(32) {
                s += "| \(c.frame) | \(c.symbol) | \(c.function) |\n"
            }
            s += "\n"
        }
        return s
    }

    private static func footer(_ r: AudioReport) -> String {
        """
        ---

        Generated by AudioIntelligence \(r.libraryVersion). Measurements are validated
        against reference implementations; estimations are statistical and may be wrong.
        """
    }
}
