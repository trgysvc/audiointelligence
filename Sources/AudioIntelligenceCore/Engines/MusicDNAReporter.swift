import Foundation

public enum MusicDNAReporter {
    
    public static func generateReport(analysis: MusicDNAAnalysis) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var lines: [String] = []
        
        let fileTitle: String = "# ✨ Elite Music DNA Infinity Audit: \(analysis.fileName)"
        lines.append(fileTitle)
        lines.append("> **Analysis Engine**: Titan UNO Native / AudioIntelligence v41.1")
        
        let dateStr: String = analysis.timestamp.formatted()
        lines.append("> **Generated**: \(dateStr) | **Latency**: Ultra-Low (ANE Optimized)")
        lines.append("")
        
        // --- 1. PRO MASTERING & LOUDNESS ---
        lines.append("## 🎚️ 1. Pro Mastering & Loudness Analytics")
        lines.append("| Metric | Value | Reference / Status |")
        lines.append("| :--- | :--- | :--- |")
        
        let intLUFS: Double = Double(analysis.mastering.integratedLUFS)
        let lufsVal: String = intLUFS.formatted(.number.precision(.fractionLength(2)))
        let lufsStatus: String = intLUFS < -14.5 ? "Low (Classic)" : "High (Streaming Standard)"
        lines.append("| **Integrated LUFS** | \(lufsVal) LUFS | \(lufsStatus) |")
        
        let momLUFS: Float = analysis.mastering.momentaryLUFS
        let momVal: String = Double(momLUFS).formatted(.number.precision(.fractionLength(2)))
        lines.append("| **Momentary Max** | \(momVal) LUFS | Energy Burst Detection |")
        
        let tpFloat: Float = analysis.mastering.truePeak
        let tpVal: String = Double(tpFloat).formatted(.number.precision(.fractionLength(2)))
        let tpStatus: String = tpFloat > -0.1 ? "⚠️ CLIPPING RISK" : "✅ HEADROOM OK"
        lines.append("| **True Peak** | \(tpVal) dBTP | \(tpStatus) |")
        
        let pCorrFloat: Float = analysis.mastering.phaseCorrelation
        let pCorr: Double = Double(pCorrFloat)
        let phaseVal: String = pCorr.formatted(.number.precision(.fractionLength(2)))
        let phaseStatus: String = pCorr < 0.7 ? "⚠️ NARROW STEREO" : "✅ WIDE & COMPATIBLE"
        lines.append("| **Phase Correlation** | \(phaseVal) | \(phaseStatus) |")
        
        let mCompOpt: Float? = analysis.mastering.monoCompatibility
        let mComp: Double = Double(mCompOpt ?? 0.0)
        let monoPct: String = (mComp * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("| **Mono Compatibility** | \(monoPct)% | Summed Integrity |")
        
        let bLRFloat: Float = analysis.mastering.balanceLR
        let bLR: Double = Double(bLRFloat)
        let balVal: String = bLR.formatted(.number.precision(.fractionLength(2)))
        let balStatus: String = abs(bLR) > 0.05 ? "⚠️ ASYMMETRIC" : "✅ CENTERED"
        lines.append("| **L/R Balance** | \(balVal) | \(balStatus) |")
        lines.append("")
        
        // --- 2. PITCH & VOCAL DNA ---
        lines.append("## 🎙️ 2. Deep Pitch & Vocal DNA")
        let pitchMean: String = Double(analysis.pitch.meanF0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Mean Fundamental (F0)**: \(pitchMean) Hz")
        lines.append("- **Pitch Range**: \(Int(analysis.pitch.minF0)) Hz - \(Int(analysis.pitch.maxF0)) Hz")
        
        let vRatio: Float = analysis.pitch.voicedRatio
        let voicePct: String = (Double(vRatio) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Voiced Ratio**: \(voicePct)% (İnsan sesi / Enstrümantal yoğunluğu)")
        
        let pStab: Float = analysis.pitch.stability
        let stabPct: String = (Double(pStab) * 100.0).formatted(.number.precision(.fractionLength(1)))
        lines.append("- **Pitch Stability**: \(stabPct)% (Entonasyon tutarlılığı)")
        lines.append("")
        
        // --- 3. EXTENDED SPECTRAL SUITE ---
        lines.append("## 🧪 3. Extended Spectral Suite")
        lines.append("- **Centroid**: \(Int(analysis.spectral.centroid)) Hz (\(analysis.spectral.brightnessDescription))")
        lines.append("- **Rolloff (85%)**: \(Int(analysis.spectral.rolloff)) Hz (High frequency tail)")
        lines.append("- **Bandwidth**: \(Int(analysis.spectral.bandwidth)) Hz (Spectral width)")
        
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
        lines.append("## 🥁 4. Ritim & Micro-Timing DNA")
        let rhythmBPM: Float = analysis.rhythm.bpm
        let bpmStr: String = Double(rhythmBPM).formatted(.number.precision(.fractionLength(2)))
        lines.append("- **Master BPM**: \(bpmStr)")
        
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
        lines.append("## 🎹 5. Tonalite & Chroma Profile")
        lines.append("**Key Detection**: \(analysis.tonality.key) (\(analysis.tonality.tendency))")
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
        
        // --- 6. FORENSIC ---
        lines.append("## 🔍 6. Forensic Röntgen (Bit-Depth Check)")
        lines.append("| Feature | Status | Analysis |")
        lines.append("| :--- | :--- | :--- |")
        
        let fIsUpsampled: Bool = analysis.forensic.isUpsampled
        let forensicStatus: String = fIsUpsampled ? "⚠️ FAKE HI-RES DETECTED" : "✅ NATIVE BIT-DEPTH"
        lines.append("| **Bit-Depth Integrity** | \(analysis.forensic.effectiveBits)-bit | \(forensicStatus) |")
        lines.append("| **Encoder Signature** | \(analysis.forensic.encoder ?? "Missing Metadata") | Potential origin footprint |")
        lines.append("| **Provenance** | \(analysis.forensic.sourceURL ?? "Offline Source") | Source tracking |")
        
        let fIsVerified: Bool = analysis.forensic.isVerified
        let verifyStatus: String = fIsVerified ? "✅ VERIFIED" : "❓ UNKNOWN"
        lines.append("| **DNA Signature** | \(verifyStatus) | Authenticity status |")
        lines.append("")
        
        // --- 7. STRUCTURE ---
        lines.append("## 🧩 7. Yapısal Segmentasyon")
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
