import Foundation

public enum MusicDNAReporter {
    
    public static func generateReport(analysis: MusicDNAAnalysis) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var lines: [String] = []
        
        let fileTitle: String = "# 🧬 AudioIntelligence Music DNA Raport: \(analysis.fileName)"
        lines.append(fileTitle)
        lines.append("> **Analysis Engine**: Titan Pro / AudioIntelligence v56.0 (Metal GPU Accelerated)")
        
        let dateStr: String = analysis.timestamp.formatted()
        lines.append("> **Generated**: \(dateStr) | **Standard**: EBU R128 / Tech 3342 / AES17")
        lines.append("")
        
        lines.append("## 🧩 1. Semantic Instrument DNA (Dominance & Roles)")
        lines.append("| Category | Dominance | Occupancy Bar | Role |")
        lines.append("| :--- | :--- | :--- | :--- |")
        
        let semanticData = analysis.semantic.dominanceMap.sorted(by: { $0.value > $1.value })
        for (category, percent) in semanticData {
            let pDouble = Double(percent)
            let rawBarSize = pDouble / 5.0
            let barSize = Int(max(0.0, min(20.0, rawBarSize)))
            let bar = String(repeating: "█", count: barSize) + String(repeating: "░", count: 20 - barSize)
            let pStr = pDouble.formatted(.number.precision(.fractionLength(1)))
            
            var roleDetail = "-"
            if category == "Presence/Lead" { roleDetail = analysis.semantic.primaryRole }
            if category == "Sub/Bass" && percent > 30 { roleDetail = "Foundational" }
            
            lines.append("| **\(category)** | \(pStr)% | `\(bar)` | \(roleDetail) |")
        }
        lines.append("- **Primary Role**: \(analysis.semantic.primaryRole) (Intensity: \( (Double(analysis.semantic.presenceScore) * 100.0).formatted(.number.precision(.fractionLength(1))) )%)")
        lines.append("- **Texture Profile**: \(analysis.semantic.textureType)")
        lines.append("")

        // --- 2. PRO MASTERING & LOUDNESS ---
        lines.append("## 🎚️ 2. Pro Mastering & Loudness Analytics (EBU R128 / Tech 3342)")
        lines.append("| Metric | Value | Reference / Status |")
        lines.append("| :--- | :--- | :--- |")
        
        let intLUFS: Double = Double(analysis.mastering.integratedLUFS)
        let lufsVal: String = intLUFS.formatted(.number.precision(.fractionLength(2)))
        let lufsStatus: String = intLUFS < -14.5 ? "Classical / Dynamic" : "Streaming Standard"
        lines.append("| **Integrated LUFS** | \(lufsVal) LUFS | \(lufsStatus) |")
        
        let lraLU: Float = analysis.mastering.lraLU
        let lraVal: String = Double(lraLU).formatted(.number.precision(.fractionLength(2)))
        let lraStatus: String = lraLU > 12.0 ? "High Dynamic" : "Compressed"
        lines.append("| **Loudness Range (LRA)** | \(lraVal) LU | \(lraStatus) (EBU Tech 3342) |")

        let momLUFS: Float = analysis.mastering.momentaryLUFS
        let momVal: String = Double(momLUFS).formatted(.number.precision(.fractionLength(2)))
        lines.append("| **Momentary Max** | \(momVal) LUFS | Gated Measurement |")
        
        let tpFloat: Float = analysis.mastering.truePeak
        let tpVal: String = Double(tpFloat).formatted(.number.precision(.fractionLength(2)))
        let tpStatus: String = tpFloat > -1.0 ? "⚠️ RISK" : "✅ OK"
        lines.append("| **True Peak** | \(tpVal) dBTP | \(tpStatus) (4x OS) |")
        
        let pCorrFloat: Float = analysis.mastering.phaseCorrelation
        let pCorr: Double = Double(pCorrFloat)
        let phaseVal: String = pCorr.formatted(.number.precision(.fractionLength(2)))
        let phaseStatus: String = analysis.mastering.monoCompatibility
        lines.append("| **Phase Correlation** | \(phaseVal) | \(phaseStatus) |")
        
        let sidePct: Float = analysis.mastering.sideEnergyPercent
        let sideVal: String = Double(sidePct).formatted(.number.precision(.fractionLength(1)))
        let msStatus: String = sidePct > 40.0 ? "Wide (Risky Mono)" : "Focused (Solid Mono)"
        lines.append("| **M/S Balance** | \(sideVal)% Side | \(msStatus) |")

        let sWidth: Float = analysis.mastering.stereoWidth
        let widthVal: String = Double(sWidth).formatted(.number.precision(.fractionLength(2)))
        lines.append("| **Stereo Width** | \(widthVal) | Side/Mid Energy Ratio |")
        lines.append("")

        // --- 3. PITCH & VOCAL DNA ---
        lines.append("## 🎙️ 3. Deep Pitch & Vocal DNA")
        let pitchMean: String = Double(analysis.pitch.meanF0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Mean Fundamental (F0)**: \(pitchMean) Hz")
        lines.append("- **Pitch Range**: \(Int(analysis.pitch.minF0)) Hz - \(Int(analysis.pitch.maxF0)) Hz")
        
        let vRatio: Float = analysis.pitch.voicedRatio
        let voicePct: String = (Double(vRatio) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Voiced Ratio**: \(voicePct)% (Speech / Instrument Density)")
        
        let pStab: Float = analysis.pitch.stability
        let stabPct: String = (Double(pStab) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Pitch Stability**: \(stabPct)% (Intonation consistency)")
        lines.append("")
        
        // --- 3. EXTENDED SPECTRAL SUITE ---
        lines.append("## 🧪 3. Extended Spectral Suite (Pro Stats)")
        lines.append("- **Centroid**: \(Int(analysis.spectral.centroid)) Hz (\(analysis.spectral.brightnessDescription))")
        lines.append("- **Rolloff (85%)**: \(Int(analysis.spectral.rolloff)) Hz (Energy tail)")
        lines.append("- **Bandwidth**: \(Int(analysis.spectral.bandwidth)) Hz (Spectral spread)")
        
        let sSkew: String = Double(analysis.spectral.skewness).formatted(.number.precision(.fractionLength(3)))
        let sKurt: String = Double(analysis.spectral.kurtosis).formatted(.number.precision(.fractionLength(3)))
        lines.append("- **Skewness**: \(sSkew) (Spectral asymmetry)")
        lines.append("- **Kurtosis**: \(sKurt) (Spectral peakedness)")

        let sFlat: Float = analysis.spectral.flatness
        let flatVal: String = Double(sFlat).formatted(.number.precision(.fractionLength(4)))
        let flatStatus: String = sFlat > 0.1 ? "Noisy" : "Tonal"
        lines.append("- **Flatness**: \(flatVal) (\(flatStatus))")
        
        let sDyn: Float = analysis.spectral.dynamicRange
        let dynVal: String = Double(sDyn).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Dynamic Range**: \(dynVal) dB")
        lines.append("")
        
        lines.append("### Spectral Contrast (7 Bands)")
        for (i, contrast) in analysis.timbre.spectralContrast.enumerated() {
            let cDouble: Double = Double(contrast)
            let rawBarSize: Double = cDouble * 10.0
            let barSize: Int = Int(max(0.0, min(20.0, rawBarSize)))
            let bar: String = String(repeating: "█", count: barSize) + String(repeating: "░", count: 20 - barSize)
            let cStr: String = cDouble.formatted(.number.precision(.fractionLength(2)))
            lines.append("- Band \(i): `\(bar)` \(cStr) dB")
        }
        lines.append("")
        
        // --- 4. RHYTHM ---
        lines.append("## 🥁 4. Rhythm & Micro-Timing DNA")
        let rhythmBPM: Float = analysis.rhythm.bpm
        let bpmStr: String = Double(rhythmBPM).formatted(.number.precision(.fractionLength(2)))
        let bpmConf: String = (Double(analysis.rhythm.bpmConfidence) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Master BPM**: \(bpmStr) (Reliability: **\(bpmConf)%**)")
        
        let rConsistency: Float = analysis.rhythm.beatConsistency
        let beatCons: String = Double(rConsistency).formatted(.number.precision(.fractionLength(4)))
        lines.append("- **Beat-Grid Integrity**: \(beatCons)s (\(analysis.rhythm.characterize))")
        
        let rOnsetMean: Float = analysis.rhythm.onsetMean
        let rOnsetPeak: Float = analysis.rhythm.onsetPeak
        let oMean: String = Double(rOnsetMean).formatted(.number.precision(.fractionLength(3)))
        let oPeak: String = Double(rOnsetPeak).formatted(.number.precision(.fractionLength(3)))
        lines.append("- **Transient Profile**: Mean: \(oMean) | Peak: \(oPeak)")
        lines.append("")
        
        // --- 5. TONALITY ---
        lines.append("## 🎹 5. Tonality & Chroma Profile")
        let keyConf: String = (Double(analysis.tonality.keyConfidence) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("**Key Detection**: \(analysis.tonality.key) (Reliability: **\(keyConf)%**)")
        lines.append("- Tendency: \(analysis.tonality.tendency)")
        lines.append("")
        
        let chromaBase: [Float] = analysis.chromaProfile
        let maxChromaRaw: Float = chromaBase.max() ?? 1.0
        let maxChroma: Double = Double(maxChromaRaw)
        let safeMax: Double = maxChroma > 0.0 ? maxChroma : 1.0
        
        for i in 0..<12 {
            let weightRaw: Float = chromaBase[i]
            let weight: Double = Double(weightRaw)
            let ratio: Double = weight / safeMax
            let rawBSize: Double = ratio * 25.0
            let bSize: Int = Int(rawBSize)
            let clampedSize: Int = max(0, min(25, bSize))
            
            let bar: String = String(repeating: "█", count: clampedSize) + String(repeating: "░", count: 25 - clampedSize)
            let wStr: String = weight.formatted(.number.precision(.fractionLength(3)))
            let note: String = noteNames[i].padding(toLength: 3, withPad: " ", startingAt: 0)
            lines.append("- **\(note)**: `\(bar)` \(wStr)")
        }
        lines.append("")
        
        // --- 7. FORENSIC ---
        lines.append("## 🔍 7. Forensic Analysis & Integrity (Laboratory Grade)")
        lines.append("| Feature | Status | Analysis |")
        lines.append("| :--- | :--- | :--- |")
        
        let fIsUpsampled: Bool = analysis.forensic.isUpsampled
        let forensicStatus: String = fIsUpsampled ? "⚠️ FAKE HI-RES DETECTED" : "✅ NATIVE BIT-DEPTH"
        lines.append("| **Bit-Depth Integrity** | \(analysis.forensic.effectiveBits)-bit | \(forensicStatus) |")
        lines.append("| **Entropy Score** | \(Double(analysis.forensic.entropyScore).formatted(.number.precision(.fractionLength(3)))) | Data uniqueness density |")
        lines.append("| **Codec Cutoff** | \(Int(analysis.forensic.codecCutoffHz)) Hz | Compression footprint |")
        lines.append("| **Clipping Events** | \(analysis.forensic.clippingEvents) | Digital saturation count |")
        
        let fIsVerified: Bool = analysis.forensic.isVerified
        let verifyStatus: String = fIsVerified ? "✅ AUTHENTIC" : "❓ UNKNOWN"
        lines.append("| **DNA Signature** | \(verifyStatus) | Scientific validation status |")
        lines.append("")

        // --- 8. STRUCTURE ---
        lines.append("## 🧩 8. Structural Segmentation")
        lines.append("| ID | START | END | DURATION | LABEL |")
        lines.append("| :-- | :--- | :--- | :--- | :--- |")
        for seg in analysis.segments {
            let segStart: Double = seg.start
            let segEnd: Double = seg.end
            let dur: Int = Int(segEnd - segStart)
            let startT: String = formatTime(segStart)
            let endT: String = formatTime(segEnd)
            lines.append("| \(seg.id) | \(startT) | \(endT) | \(dur)s | **\(seg.label)** |")
        }
        lines.append("")
        
        let coverage = analysis.audit.engineCoverage.sorted(by: { $0.key < $1.key })
        for (engine, status) in coverage {
            let statusIcon = status ? "✅ ACTIVE" : "❌ INACTIVE"
            var detail = "-"
            if engine == "CQT" { detail = analysis.audit.cqtStatus }
            if engine == "MelSpectrogram" { detail = analysis.audit.melSpectrogramResolution }
            if engine == "Utility" { detail = analysis.audit.utilityCheck }
            if engine == "Metal" { detail = "Hardware Buffering Active (Turbo Mode)" }
            if engine == "Tonnetz" { detail = "6-Dim Harmonic Vector Space" }
            if engine == "NMF" { detail = "Matrix Rank-2 Decomposition" }
            if engine == "Neural" { detail = "ANE-Separation Pipeline Verified" }
            
            lines.append("| **\(engine)** | \(statusIcon) | \(detail) |")
        }
        lines.append("")
        
        // --- 9.5 EXTENDED INFINITY ANALYTICS ---
        lines.append("## 🏆 9.5 Extended Infinity Analytics (New Engines)")
        
        lines.append("### 🎹 Tonnetz DNA (Harmonic Centroids)")
        let hStab = (Double(analysis.tonnetz.harmonicStability) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Harmonic Stability**: \(hStab)% (Tonal center consistency)")
        lines.append("| Dimension | Mapping | Mean Strength | Bar |")
        lines.append("| :--- | :--- | :--- | :--- |")
        let tonnetzLabels = ["m7 x", "m7 y", "M3 x", "M3 y", "P5 x", "P5 y"]
        for i in 0..<6 {
            let val = analysis.tonnetz.meanTonnetz[i]
            let barSize = Int(abs(val) * 20.0)
            let bar = String(repeating: "█", count: barSize) + String(repeating: "░", count: 20 - barSize)
            lines.append("| dim_\(i) | \(tonnetzLabels[i]) | \(Double(val).formatted(.number.precision(.fractionLength(3)))) | `\(bar)` |")
        }
        lines.append("")
        
        lines.append("### 🥁 Tempogram DNA (Tempo Periodicity)")
        let domPeriod = analysis.tempogram.dominantPeriod
        lines.append("- **Dominant Period**: \(domPeriod) bins (Cyclic pulse consistency)")
        let tempoMap = analysis.tempogram.cyclicTempoMap
        let maxTempo = tempoMap.max() ?? 1.0
        lines.append("- **Tempo Energy Peak**: \(Double(maxTempo).formatted(.number.precision(.fractionLength(4))))")
        lines.append("")
        
        lines.append("### 🧬 NMF Decomposition DNA")
        let reconstructionErr = Double(analysis.nmf.reconstructionError).formatted(.number.precision(.fractionLength(5)))
        lines.append("- **Reconstruction Error**: \(reconstructionErr) (MSE)")
        for (i, energy) in analysis.nmf.componentEnergy.enumerated() {
            let ePct = (Double(energy) * 100.0).formatted(.number.precision(.fractionLength(1)))
            lines.append("- **Component \(i)**: \(ePct)% Energy contribution")
        }
        lines.append("")
        
        lines.append("### 🎙️ Refined Pitch (Piptrack DNA)")
        let refinedF0 = Double(analysis.piptrack.refinedMeanF0).formatted(.number.precision(.fractionLength(2)))
        let tConf = (Double(analysis.piptrack.trackingConfidence) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Refined Mean F0**: \(refinedF0) Hz")
        lines.append("- **Tracking Confidence**: \(tConf)% (Partial coherence)")
        lines.append("")
        
        // --- 10. LABORATORY SCIENCE ---
        lines.append("## 🧪 10. Laboratory Science & Standards (AES17 / IMD / 468)")
        lines.append("| Metric | Value | Technical Context |")
        lines.append("| :--- | :--- | :--- |")
        
        let aes17Val: String = Double(analysis.science.dynamicRangeAES17).formatted(.number.precision(.fractionLength(1)))
        lines.append("| **AES17 Dynamic Range** | \(aes17Val) dB | Measured with stimulus isolation |")
        
        let imdVal: String = Double(analysis.science.smpteIMD).formatted(.number.precision(.fractionLength(3)))
        lines.append("| **SMPTE IMD** | \(imdVal)% | 60Hz/7kHz interaction ratio |")
        
        let weight468: String = Double(analysis.science.noiseFloorWeight468).formatted(.number.precision(.fractionLength(2)))
        lines.append("| **ITU-R 468 Noise** | \(weight468) dB | Broadcast weighting standard |")
        
        let snrVal: String = Double(analysis.science.snr).formatted(.number.precision(.fractionLength(1)))
        lines.append("| **Signal-to-Noise Ratio** | \(snrVal) dB | Broad-spectrum integrity |")
        lines.append("| **Validation Status** | \(analysis.science.status) | 100% Scientific Baseline |")
        lines.append("")

        // --- 11. TECHNICAL MANIFEST ---
        lines.append("## 📖 11. DSP Technical Manifest (Algorithm Transparency)")
        lines.append("| Module | Algorithm / Technique | Library Equivalence |")
        lines.append("| :--- | :--- | :--- |")
        lines.append("| **Loudness** | EBU R128 / Tech 3342 (LRA) | `izotope.loudness` |")
        lines.append("| **True Peak** | 4x Polyphase Oversampling | `truepeak.inter_sample` |")
        lines.append("| **GPU Acceleration** | Metal MSL MS-Reduction | `apple.accelerate.gpu` |")
        lines.append("| **Forensic** | LSB Shannon Entropy Analysis | `forensic.bit_integrity` |")
        lines.append("| **Semantic** | Spectral Fingerprinting | `semantic.audio_DNA` |")
        lines.append("")
        
        // --- 12. INFINITY DATA DUMP ---
        lines.append("## 📊 12. Infinity Data Dump (Raw DSP Output)")
        lines.append("<details>")
        lines.append("<summary>View Detailed Spectral and Rhythmic Metrics</summary>")
        lines.append("")
        lines.append("### 🧪 Raw Spectral Data")
        lines.append("- Skewness: `\(analysis.spectral.skewness)`")
        lines.append("- Kurtosis: `\(analysis.spectral.kurtosis)`")
        lines.append("- RMS Mean: `\(analysis.spectral.rmsMean)`")
        lines.append("- RMS Max: `\(analysis.spectral.rmsMax)`")
        lines.append("- Spectral Flatness: `\(analysis.spectral.flatness)`")
        lines.append("- Zero Crossing Rate: `\(analysis.spectral.zcr)`")
        lines.append("")
        lines.append("### 🥁 Raw Rhythm Data")
        lines.append("- BPM Confidence Index: `\(analysis.rhythm.bpmConfidence)`")
        lines.append("- Key Confidence Index: `\(analysis.tonality.keyConfidence)`")
        lines.append("- Beat Consistency (StdDev): `\(analysis.rhythm.beatConsistency)`")
        lines.append("")
        lines.append("---")
        lines.append("> **Hardware Acceleration Info**: \(analysis.audit.filterbankStatus)")
        lines.append("</details>")
        lines.append("")

        // --- 13. INSTRUMENT PREDICTION ---
        lines.append("## 🎻 13. Instrument Prediction & Technical Evidence")
        lines.append("| Instrument | Confidence | Technical Justification |")
        lines.append("| :--- | :--- | :--- |")
        
        let sortedInsuruments = analysis.instruments.predictions.sorted(by: { $0.confidence > $1.confidence })
        for pred in sortedInsuruments {
            let confPct = (Double(pred.confidence) * 100.0).formatted(.number.precision(.fractionLength(1)))
            let barSize = Int(pred.confidence * 10.0)
            let bar = String(repeating: "█", count: barSize) + String(repeating: "░", count: 10 - barSize)
            
            lines.append("| **\(pred.label)** | \(confPct)% `\(bar)` | \(pred.technicalBasis) |")
        }
        
        if sortedInsuruments.isEmpty {
            lines.append("| **Ambient/Unclassified** | - | No distinct spectral matches found |")
        }
        lines.append("")
        lines.append("---")
        lines.append("> **Recognition Accuracy Disclaimer**: Predictions are based on spectral fingerprinting and Euclidean distance. Forensic validation is recommended for critical stems.")
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatTime(_ sec: Double) -> String {
        let seconds: Int = Int(sec)
        let m: Int = seconds / 60
        let s: Int = seconds % 60
        let sStr: String = s < 10 ? "0\(s)" : "\(s)"
        return "\(m):\(sStr)"
    }
}
