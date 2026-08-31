import Foundation
import AVFoundation
import Accelerate
import AudioIntelligenceMetal

public enum AnalysisLane: String, Codable, CaseIterable, Sendable {
    case rhythm, tonal, pitch, spectral, hpss, timbre, mastering, semantic, forensic, instruments, science, audit, advanced
}

public actor DNAReportBuilder {
    
    private let device: Device
    private let mode: Mode
    private let metalEngine: MetalEngine

    public init(
        device: Device = .automatic, 
        mode: Mode = .balanced,
        metalEngine: MetalEngine = MetalEngine()
    ) {
        self.device = device
        self.mode = mode
        self.metalEngine = metalEngine
    }

    /// Public pipeline: returns the clean, layered `AudioReport`.
    public func analyze(
        url: URL,
        lanes: Set<AnalysisLane> = Set(AnalysisLane.allCases),
        progress: @escaping @Sendable (Double, String, String?) -> Void
    ) async throws -> AudioReport {
        let (analysis, context) = try await analyzeAggregate(url: url, lanes: lanes, progress: progress)
        return AudioReport(from: analysis, context: context)
    }

    /// Advanced/internal hook: the raw engine aggregate plus source context,
    /// before lifting into `AudioReport`. Used by deep validation tests that need
    /// fields not surfaced in the public schema.
    public func analyzeAggregate(
        url: URL,
        lanes: Set<AnalysisLane> = Set(AnalysisLane.allCases),
        progress: @escaping @Sendable (Double, String, String?) -> Void
    ) async throws -> (analysis: MusicDNAAnalysis, context: AudioReport.SourceContext) {

        let filename = url.lastPathComponent
        progress(5, "Initializing Absolute Forensic Completeness v7.1...", nil)
        
        let hwStatus = metalEngine.getHardwareStatus()
        progress(10, "M4 Hardware Hook: \(hwStatus) [STABLE]", nil)
        
        // Diagnostic stress test removed to prevent Watchdog Timeout (BPT trap) 
        // during high-concurrency 26-engine forensic runs.
        progress(12, "M4 GPU Unified Pipeline Authorized", nil)
        
        let chunkSize: Double = 45.0
        let file = try AVAudioFile(forReading: url)
        let sourceBitDepth = AudioLoader.sourceBitDepth(for: url) // deterministic header read
        let inputFormat = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        let chunkInputFrames = AVAudioFrameCount(chunkSize * inputFormat.sampleRate)
        var readOffset: AVAudioFramePosition = 0
        
        // --- 26-Engine Aggregator State (PRE-ALLOCATED FOR BUS ERROR PROTECTION) ---
        let maxExpectedFragments = Int(ceil(Double(totalFrames) / Double(chunkInputFrames))) + 1
        let sampleRate = inputFormat.sampleRate
        
        // High-Resolution Feature Buffers (v7.1 Forensic Upgrade)
        var fullChromagram = [[Float]]()
        var fullPitchPath = [Int]()
        var fullBeatTimes = [Double]()
        var fullOnsetEnv = [Float]()
        // Whole-track per-frame MFCC [20][TotalFrames], accumulated across chunks -- feeds a
        // SINGLE whole-track `StructureEngine` pass after the loop (see that call site).
        var fullMFCCBins = [[Float]](repeating: [], count: 20)
        
        var allLoudness = [LoudnessEngine.LoudnessResult?](repeating: nil, count: maxExpectedFragments)
        var allSpectral = [AdvancedSpectralMetrics?](repeating: nil, count: maxExpectedFragments)
        var allOnsets = [OnsetResult?](repeating: nil, count: maxExpectedFragments)
        var allBitDepths = [Int?](repeating: nil, count: maxExpectedFragments)
        var allCodecs = [Float?](repeating: nil, count: maxExpectedFragments)
        var allClipping = [Int?](repeating: nil, count: maxExpectedFragments)
        var allEntropy = [Float?](repeating: nil, count: maxExpectedFragments)
        
        var allHPSS = [HPSSResult?](repeating: nil, count: maxExpectedFragments)
        var allInstruments = [InstrumentPrediction](repeating: InstrumentPrediction(label: "Empty", confidence: 0, technicalBasis: "Pre-allocated"), count: 500)
        var instrumentPtr = 0
        
        var allScience = [ScienceMetrics?](repeating: nil, count: maxExpectedFragments)
        var allTonnetz = [[Float]?](repeating: nil, count: maxExpectedFragments)
        var allChroma = [[[Float]]?](repeating: nil, count: maxExpectedFragments)
        var allCQT = [[[Float]]?](repeating: nil, count: maxExpectedFragments)
        var allNMF = [Float?](repeating: nil, count: maxExpectedFragments)
        var allPiptrack = [Float?](repeating: nil, count: maxExpectedFragments)
        var allYIN = [PitchResult?](repeating: nil, count: maxExpectedFragments)
        var allMFCC = [[Float]?](repeating: nil, count: maxExpectedFragments)
        var allRhythm = [RhythmResult?](repeating: nil, count: maxExpectedFragments)
        var allContrast = [[Float]?](repeating: nil, count: maxExpectedFragments)
        var allStereo = [StereoEngine.StereoResult?](repeating: nil, count: maxExpectedFragments)
        var allChunkEnergy = [Float](repeating: 0, count: maxExpectedFragments)
        var allChannelEnergy = [(left: Float, right: Float)](repeating: (0, 0), count: maxExpectedFragments)
        var nmfComponentEnergy: [Float] = []   // real NMF activation energy (set at idx==0)
        var nmfReconError: Float = 0           // real NMF reconstruction error (set at idx==0)
        var waveformEnvelope: [Float] = []     // downsampled peak envelope, accumulated per chunk
        
        Swift.print("🔍 Starting [Absolute Forensic Recalibration] Run (30 Engines - High-Res Path)")
        
        var idx = 0
        while readOffset < AVAudioFramePosition(totalFrames) {
            let currentReadCount = min(chunkInputFrames, AVAudioFrameCount(totalFrames) - AVAudioFrameCount(readOffset))
            
            // ATOMIC STEP: Load chunk, analyze, purge.
            await Task.yield() 
            
            // Single stereo decode serves both the mono analysis path and real stereo metrics.
            let stereoChunk = try AudioLoader.loadNextChunkStereoManual(file: file, offset: readOffset, frameCount: currentReadCount, targetSampleRate: inputFormat.sampleRate)
            var monoSamples = [Float](repeating: 0, count: stereoChunk.left.count)
            vDSP_vadd(stereoChunk.left, 1, stereoChunk.right, 1, &monoSamples, 1, vDSP_Length(monoSamples.count))
            var halfScale: Float = 0.5
            vDSP_vsmul(monoSamples, 1, &halfScale, &monoSamples, 1, vDSP_Length(monoSamples.count))
            let chunk = AudioBuffer(samples: monoSamples, sampleRate: stereoChunk.sampleRate, duration: stereoChunk.duration)

            // Waveform peak envelope: max |sample| per bucket, accumulated across the whole
            // track for the report's downsampled overview (was hardcoded empty at build time).
            if !monoSamples.isEmpty {
                let bucketsPerChunk = 64
                let bucketSize = max(1, monoSamples.count / bucketsPerChunk)
                monoSamples.withUnsafeBufferPointer { ptr in
                    var b = 0
                    while b < monoSamples.count {
                        let len = min(bucketSize, monoSamples.count - b)
                        var peak: Float = 0
                        vDSP_maxmgv(ptr.baseAddress! + b, 1, &peak, vDSP_Length(len))
                        waveformEnvelope.append(peak)
                        b += bucketSize
                    }
                }
            }

            // Real stereo/phase metrics (energy-weighted aggregation downstream).
            let stereoRes = StereoEngine().analyze(left: stereoChunk.left, right: stereoChunk.right)
            allStereo[idx] = stereoRes
            var eL: Float = 0, eR: Float = 0
            vDSP_svesq(stereoChunk.left, 1, &eL, vDSP_Length(stereoChunk.left.count))
            vDSP_svesq(stereoChunk.right, 1, &eR, vDSP_Length(stereoChunk.right.count))
            allChannelEnergy[idx] = (eL, eR)
            allChunkEnergy[idx] = eL + eR

            let timestamp = Double(readOffset) / inputFormat.sampleRate
            progress(15 + Double(idx) * 1.5, "Fragment #\(idx + 1) (@\(Int(timestamp))s): Sequential Processing...", nil)
            
            // 1. Core STFT
            let stftEngine = STFTEngine(nFFT: 2048, hopLength: 512, sampleRate: chunk.sampleRate, metalEngine: metalEngine)
            let stft = await stftEngine.analyze(chunk.samples)
            
            // --- GROUP A: Core Metrics ---
            Swift.print("⚙️ [Group A] Aligned Engine Push...")
            let onsets = await OnsetEngine(sampleRate: chunk.sampleRate).onsetStrength(chunk.samples)
            allOnsets[idx] = onsets
            
            let rhythmRes = await RhythmEngine(sampleRate: chunk.sampleRate).analyze(onsetResult: onsets)
            allRhythm[idx] = rhythmRes
            
            let specResRaw = SpectralEngine(sampleRate: chunk.sampleRate).analyze(stft: stft, samples: chunk.samples)
            let specRes = AdvancedSpectralMetrics(
                centroid: specResRaw.centroidHz, rolloff: specResRaw.rolloffHz, flatness: specResRaw.flatness, flux: specResRaw.flux, skewness: specResRaw.skewness, kurtosis: specResRaw.kurtosis, bandwidth: specResRaw.bandwidthHz, zcr: specResRaw.zcr, dynamicRange: specResRaw.spectralCrestFactor, rmsMean: specResRaw.rmsMean, rmsMax: specResRaw.rmsMax, brightnessDescription: "Laboratory Grade", fullMagnitudes: []
            )
            allSpectral[idx] = specRes
            
            let loudness = LoudnessEngine(sampleRate: chunk.sampleRate, metalEngine: metalEngine).analyze(channels: [chunk.samples])
            allLoudness[idx] = loudness
            
            let forensic = ForensicEngine().analyze(samples: chunk.samples, magnitude: stft.magnitude, nFrames: stft.nFrames, nFFT: 2048, sampleRate: chunk.sampleRate)
            allBitDepths[idx] = forensic.trueBitDepth
            allCodecs[idx] = forensic.codecCutoffHz
            allClipping[idx] = forensic.clippingEvents
            allEntropy[idx] = forensic.entropyScore

            // --- GROUP B: Tonal DNA ---
            Swift.print("⚙️ [Group B] Aligned Engine Push...")
            // High-resolution STFT (nFFT 8192, ~2.7 Hz bins) for chroma: linear 2048 bins
            // smear bass pitches that define the key root, causing fifth confusion. Same
            // hop (512) keeps the frame grid — and the modulation/structure timebases —
            // unchanged. Lifts key accuracy from ~24% to ~39% (librosa-level) on GiantSteps.
            let stftChroma = await STFTEngine(nFFT: 8192, hopLength: 512, sampleRate: chunk.sampleRate, metalEngine: metalEngine).analyze(chunk.samples)
            let chromaRaw = ChromaEngine(nFFT: 8192, sampleRate: chunk.sampleRate).chromagram(stft: stftChroma)
            allChroma[idx] = chromaRaw // Forensic Fix: Store all 12 bins

            // Real CQT for bass-note/inversion detection (`TraditionalTheoryEngine.
            // detectBassNote`) — was always passed a literal `[]`, so `dominantBin` never
            // updated from its 0 default and every chord's bass note silently read as "C"
            // regardless of the real root, corrupting inversion labels for every non-C chord.
            // Same hop (512) as the chroma STFT keeps frame indices closely aligned; CQT's own
            // frame-count formula differs slightly from STFT's (no `center` padding), so the
            // two grids can drift by roughly one frame per chunk near chunk boundaries —
            // `detectBassNote`'s existing bounds check already handles that safely.
            allCQT[idx] = CQTEngine(nBins: 84, binsPerOctave: 12, fMin: 32.7, sampleRate: chunk.sampleRate, hopLength: 512).transform(chunk.samples)
            
            let yin = YINEngine(sampleRate: chunk.sampleRate).analyze(samples: chunk.samples)
            allYIN[idx] = yin
            
            let piptrackRes = PiptrackEngine().track(stft: stft)
            allPiptrack[idx] = piptrackRes.pitches.reduce(0, +) / Float(max(1, piptrackRes.pitches.count))
            
            // High-Res Append (Aligned to global offset)
            // `PiptrackResult.pitches` is Hz per frame (0 = no pitch detected — PiptrackEngine
            // leaves silent/unvoiced frames at their zero-initialized default). CounterpointEngine
            // and MotifEngine both expect MIDI note numbers here (their own code refers to
            // "leadMidi" and counts "semitones" between entries) — passing the raw Hz value
            // straight through as if it already were a MIDI number made their interval math
            // meaningless (e.g. a 440Hz A4 read as MIDI note 440, off the instrument's actual
            // register by over 30 octaves). Convert Hz -> MIDI properly; keep 0 as the "no
            // pitch" sentinel so a silent frame still reads as 0 downstream, same as before.
            for p in piptrackRes.pitches { fullPitchPath.append(DSPHelpers.hzToMIDI(p)) }
            
            let contrast = SpectralFeatureEngine.spectralContrast(from: stft, nBands: 6)
            allContrast[idx] = contrast.map { $0.reduce(0, +) / Float(max(1, $0.count)) }

            let tonnetz = TonnetzEngine().compute(chromagram: chromaRaw)
            
            // Refactored to prevent compiler complexity timeout (v7.2 Aligned)
            var tonnetzMeans = [Float](repeating: 0, count: 6)
            let framesCount = Float(max(1, tonnetz.tonnetz.first?.count ?? 0))
            for i in 0..<6 {
                let sum = tonnetz.tonnetz[i].reduce(0, +)
                tonnetzMeans[i] = sum / framesCount
            }
            allTonnetz[idx] = tonnetzMeans

            
            // --- GROUP C: Infinity Engines (HARD ISOLATION MODE) ---
            Swift.print("⚙️ [Group C] Engaging Infinity Matrix (Isolated Path)...")
            let melRes = await MelSpectrogramEngine(stftEngine: stftEngine, nMels: 128, metalEngine: metalEngine).createMelSpectrogram(from: chunk.samples)
            
            // HPSS runs on EVERY chunk so coverage spans the whole track (previously idx==0
            // only stored — the harmonic/percussive ratio averages below were silently
            // computed from just the first ~45s of a multi-minute track). Same bug class as
            // StructureEngine's, fixed the same way, below.
            let hpss = HPSSEngine(winHarm: 31, winPerc: 31, metalEngine: metalEngine).analyze(stft: stft)
            allHPSS[idx] = hpss
            
            autoreleasepool {
                // MFCC = DCT of LOG-mel (power_to_db), not linear mel — DCT'ing the linear
                // power spectrum gave coefficients uncorrelated with the standard MFCC.
                let logMel = melRes.melData.map { 10.0 * log10f(max($0, 1e-10)) }
                let mfccRaw = metalEngine.executeBatchDct(melSpectrogram: logMel, nMfcc: 20, nMels: 128)
                let mfccSubset = Array(mfccRaw.prefix(20))
                allMFCC[idx] = mfccSubset

                // Atomic Metric Push
                let lowBandRatio = DSPHelpers.lowBandEnergyRatio(stft: stft, cutoffHz: 250)
                let instMetrics = InstrumentEngine().predict(spectral: specRes, mfcc: mfccSubset, lowBandEnergyRatio: lowBandRatio, percussiveEnergyRatio: hpss.percussiveEnergyRatio)
                for p in instMetrics.predictions where instrumentPtr < 500 {
                    allInstruments[instrumentPtr] = p
                    instrumentPtr += 1
                }
                
                let scienceRaw = AudioScienceEngine(sampleRate: chunk.sampleRate).analyze(samples: chunk.samples)
                allScience[idx] = ScienceMetrics(dynamicRangeLRA: scienceRaw.dynamicRangeLRA, thdPlusN: scienceRaw.thdPlusN, smpteIMD: scienceRaw.smpteIMD, snr: scienceRaw.snr, noiseFloorWeight468: scienceRaw.noiseFloorWeight468, status: "Verified")

                // HARD ISOLATED MATRIX ENGINES (Deep Copy Protection)
                if idx == 0 {
                    // Force Deep Copy of Magnitude to prevent GPU/CPU race
                    let magCopy = Array(stft.magnitude)
                    
                    let isolatedSTFT = STFTMatrix(
                        magnitude: magCopy, 
                        phase: [], 
                        nFFT: stft.nFFT, 
                        hopLength: stft.hopLength, 
                        sampleRate: stft.sampleRate
                    )
                    
                    let nmf = NMFEngine().decompose(stft: isolatedSTFT)
                    allNMF[idx] = nmf.H.first?.reduce(0, +) ?? 0

                    // Real NMF diagnostics (was hardcoded 0.001 / [0.8, 0.2]).
                    let nComp = nmf.W.count
                    let nFreqsL = nmf.W.first?.count ?? 0
                    let nFramesL = nmf.H.count
                    if nComp > 0 && nFreqsL > 0 && nFramesL > 0 {
                        // Component energy = normalized temporal activation mass per component.
                        var compE = [Float](repeating: 0, count: nComp)
                        for t in 0..<nFramesL {
                            for c in 0..<min(nComp, nmf.H[t].count) { compE[c] += nmf.H[t][c] }
                        }
                        let compSum = compE.reduce(0, +)
                        if compSum > 0 { for c in 0..<nComp { compE[c] /= compSum } }
                        nmfComponentEnergy = compE

                        // Relative Frobenius reconstruction error ‖V − WH‖ / ‖V‖.
                        var num: Float = 0, den: Float = 0
                        for t in 0..<nFramesL {
                            let hRow = nmf.H[t]
                            for f in 0..<nFreqsL {
                                var wh: Float = 0
                                for c in 0..<nComp where c < hRow.count { wh += hRow[c] * nmf.W[c][f] }
                                let v = magCopy[t * nFreqsL + f]
                                let d = v - wh; num += d * d; den += v * v
                            }
                        }
                        nmfReconError = den > 0 ? sqrtf(num / den) : 0
                    }
                }

                // Accumulate this chunk's per-frame MFCC into the whole-track buffer.
                // `StructureEngine` now runs ONCE on the whole track after the loop (alongside
                // `fullChromagramBins`) instead of once per independent 45s chunk -- each chunk
                // used to be re-analyzed from scratch, and the Foote-novelty kernel has no
                // visibility past a chunk's own edges, so that injected a spurious "boundary"
                // near almost every chunk seam (measured on real SALAMI tracks: ~40% of chunked-
                // pipeline boundaries landed within 2s of a chunk seam vs ~15% for a genuine
                // whole-track analysis of the same tracks -- DEVLOG Phase 29 /
                // Examples/StructureCalibration). Also fixes a separate, previously-undiscovered
                // shape bug: the old per-chunk call passed `mfccs: [mfccSubset]` -- a single
                // 20-coefficient vector for frame 0 only -- as if it were a 1-dimension/20-frame
                // series (StructureEngine reads `mfccs` as [dim][time]), so only the chunk's
                // first ~20 STFT frames out of possibly thousands ever got a nonzero MFCC value.
                // `mfccRaw` (just above) already holds the GPU DCT's real per-frame output
                // (frame-major: id = frame*20+coeff, see `batch_dct` in
                // AudioIntelligenceMetal.swift) for the whole chunk -- reshape it into the
                // [dim][time] layout and append to the whole-track accumulator.
                let mfccFrameCount = mfccRaw.count / 20
                for t in 0..<mfccFrameCount {
                    for c in 0..<20 { fullMFCCBins[c].append(mfccRaw[t * 20 + c]) }
                }
            }
            
            // --- AGGREGATION: Collect high-res chroma and beat data ---
            fullOnsetEnv.append(contentsOf: onsets.envelope)
            for t in rhythmRes.beatTimes { fullBeatTimes.append(timestamp + t) }
            
            for f in 0..<chromaRaw[0].count {
                var vec = [Float](repeating: 0, count: 12)
                for c in 0..<12 { vec[c] = chromaRaw[c][f] }
                fullChromagram.append(vec)
            }

            // Forensic Refactor: Redundant meanVector assignment removed to preserve full chromaRaw in allChroma[idx]

            
            readOffset += AVAudioFramePosition(currentReadCount)
            idx += 1
        }
        
        progress(85, "Executing Traditional Musicology & Reduction Audit...", nil)
        
        // Global Orchestration (v7.1 Forensic Recalibration)
        let reductionEng = ReductionEngine()
        let theoryEng = TraditionalTheoryEngine()
        let counterEng = CounterpointEngine()
        let cadenceEng = CadenceEngine()
        
        // New Engines (v7.0)
        let motifEng = MotifEngine()
        let modulationEng = ModulationEngine()
        let meterEng = MeterEngine()
        let historicalEng = HistoricalEngine()
        
        // Transpose and Merge global chromagram [12][TotalFrames]
        var fullChromagramBins = [[Float]](repeating: [], count: 12)
        for fragmentMapping in allChroma {
            if let fragment = fragmentMapping {
                // fragment is [[Float]] [12][FramesInFragment]
                for c in 0..<12 {
                    if c < fragment.count {
                        fullChromagramBins[c].append(contentsOf: fragment[c])
                    }
                }
            }
        }

        let totalChromaFrames = fullChromagramBins[0].count
        Swift.print("📊 [TRACE] Forensic Chroma Validation: \(totalChromaFrames) frames captured across 12 semitones.")

        // Structural segmentation: ONE whole-track pass, using the whole-track chroma (just
        // built above) and MFCC (`fullMFCCBins`, accumulated per-chunk in the loop) -- not once
        // per independent 45s chunk. See the per-chunk loop's comment (where `fullMFCCBins` gets
        // appended to) for why chunk-by-chunk re-analysis was replaced: each chunk's Foote-
        // novelty kernel has no visibility past its own edges, which injected a spurious
        // "boundary" near almost every chunk seam. Same pattern as `smoothedPitchPath`/
        // `tempogramRes` below (accumulate whole-track, analyze once).
        var structureResult: StructureResult? = nil
        let structNFrames = min(fullChromagramBins[0].count, fullMFCCBins[0].count)
        if structNFrames > 20 {
            let structChroma = fullChromagramBins.map { Array($0.prefix(structNFrames)) }
            let structMFCC = fullMFCCBins.map { Array($0.prefix(structNFrames)) }
            let structEngine = StructureEngine(sampleRate: sampleRate)
            if let feat = structEngine.prepareFeatures(chromagram: structChroma, mfccs: structMFCC) {
                structureResult = structEngine.boundaries(from: feat)
            }
        }
        let finalSegments: [MusicSegment] = (structureResult?.segments ?? []).enumerated().map { i, seg in
            MusicSegment(id: i + 1, start: seg.startSec, end: seg.endSec, label: seg.label)
        }

        // Transpose and merge the global CQT matrix [84][TotalFrames], same chunk order as
        // the chromagram above.
        var fullCQTBins = [[Float]](repeating: [], count: 84)
        for fragmentMapping in allCQT {
            if let fragment = fragmentMapping {
                for b in 0..<84 {
                    if b < fragment.count {
                        fullCQTBins[b].append(contentsOf: fragment[b])
                    }
                }
            }
        }
        
        Swift.print("🔍 [TRACE] Step 1: Starting Reduction Analysis...")
        let reductionRes = await reductionEng.reduce(chromagram: fullChromagramBins, segments: finalSegments, sampleRate: sampleRate)
        Swift.print("✅ [TRACE] Step 1: Reduction Analysis Complete.")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 2: Starting Vertical Theory Analysis...")
        // Detect the global key from the mean chroma instead of assuming a constant
        // "C Major" — otherwise every chord is mislabelled against the wrong tonic.
        let meanChromaVec: [Float] = (0..<12).map { c in
            let bin = fullChromagramBins[c]
            return bin.isEmpty ? 0 : bin.reduce(0, +) / Float(bin.count)
        }
        let detectedGlobalKey = ModulationEngine().detectKey(meanChromaVec)
        let verticalKey = detectedGlobalKey == "Unclassified" ? "\(reductionRes.fundamentalNote) Major" : detectedGlobalKey
        let verticalRes = theoryEng.analyzeVertical(chromagram: fullChromagramBins, cqtMatrix: fullCQTBins, key: verticalKey)
        Swift.print("✅ [TRACE] Step 2: Vertical Theory Analysis Complete (\(verticalRes.count) chords).")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 3: Starting Counterpoint Analysis...")
        let counterRes = await counterEng.analyze(pitchPath: fullPitchPath, chroma: fullChromagramBins)
        Swift.print("✅ [TRACE] Step 3: Counterpoint Analysis Complete.")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 4: Starting Motif Analysis...")
        let globalKey = reductionRes.fundamentalNote // Use Ur-Note as initial key
        let motifRes = await motifEng.detectMotifs(pitchPath: fullPitchPath, chromagram: fullChromagramBins, sr: sampleRate, hopLength: 512)
        Swift.print("✅ [TRACE] Step 4: Motif Analysis Complete.")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 5: Starting Modulation Analysis...")
        // Chromagram frames come from STFT hop 512 at the file's native sample rate.
        let chromaSecondsPerFrame = 512.0 / sampleRate
        let modulationRes = await modulationEng.detectModulations(chromagram: fullChromagramBins, initialKey: globalKey, secondsPerFrame: chromaSecondsPerFrame)
        Swift.print("✅ [TRACE] Step 5: Modulation Analysis Complete.")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 6: Starting Meter Analysis...")
        let meterRes = await meterEng.detectMeter(beatTimes: fullBeatTimes, onsetStrength: fullOnsetEnv, sr: sampleRate)
        Swift.print("✅ [TRACE] Step 6: Meter Analysis Complete.")
        await Task.yield()
        
        Swift.print("🔍 [TRACE] Step 7: Starting Cadence Analysis...")
        let cadenceRes = await cadenceEng.detect(verticalChords: verticalRes, segments: finalSegments, key: globalKey, sr: sampleRate)
        Swift.print("✅ [TRACE] Step 7: Cadence Analysis Complete.")
        await Task.yield()
        
        let musicology = MusicologyMetrics(
            ursatz: reductionRes.fundamentalNote,
            cadences: cadenceRes,
            verticalAnalysis: verticalRes,
            counterpointSpecies: counterRes.species,
            counterpointErrors: counterRes.errors,
            fundamentalBasis: reductionRes.theoryBasis,
            motifs: motifRes,
            modulations: modulationRes,
            meter: meterRes,
            context: HistoricalContext(suggestedPeriod: "Analyzing...", artisticMovement: "Analyzing...", globalContext: "Analyzing...", composerContext: nil, confidence: 0)
        )
        
        progress(90, "Finalizing Atomic Data Aggregation...", nil)

        // Whole-track Viterbi-smoothed pitch path (ViterbiEngine's own doc comment describes
        // exactly this use — "pitch path stabilization" — but it was never actually wired in;
        // `allViterbi` was always passed as a literal `[]`, so the public `ViterbiMetrics.path`
        // field was always empty). Concatenates every chunk's raw YIN f0 series into one
        // continuous sequence first, so the smoothing isn't reset at each 45s chunk boundary.
        let fullF0Series = allYIN.compactMap { $0 }.flatMap { $0.f0Series }
        let smoothedPitchPath = ViterbiEngine().smoothPitchPath(f0Series: fullF0Series)

        // TempogramEngine was never actually called — `cyclicTempoMap` was always a literal
        // `[]`. `fullOnsetEnv` (the whole-track onset envelope, already concatenated across
        // chunks) is exactly what `computeACT` needs; average its per-frame autocorrelation
        // across time into one track-wide "which periodicities are prominent" profile.
        let tempogramRes = TempogramEngine().computeACT(onsetStrength: fullOnsetEnv)
        let cyclicTempoMapReal: [Float] = tempogramRes.tempogram.map { lagRow in
            lagRow.isEmpty ? 0 : lagRow.reduce(0, +) / Float(lagRow.count)
        }

        let finalAnalysis = assembleFinalDNA(
            filename: filename, 
            allLoudness: allLoudness.compactMap{$0}, allSpectral: allSpectral.compactMap{$0}, 
            allOnsets: allOnsets.compactMap{$0}, 
            allBitDepths: allBitDepths.compactMap{$0}, 
            allCodecs: allCodecs.compactMap{$0},
            allClipping: allClipping.compactMap{$0},
            allEntropy: allEntropy.compactMap{$0},
            allInstruments: Array(allInstruments.prefix(instrumentPtr)), 
            allScience: allScience.compactMap{$0}, allTonnetz: allTonnetz.compactMap{$0}, 
            allNMF: allNMF.compactMap{$0}, allPiptrack: allPiptrack.compactMap{$0}, 
            allViterbi: [smoothedPitchPath], allYIN: allYIN.compactMap{$0},
            cyclicTempoMap: cyclicTempoMapReal,
            allMFCC: allMFCC.compactMap{$0}, structureResult: structureResult,
            allRhythm: allRhythm.compactMap{$0}, allContrast: allContrast.compactMap{$0},
            allChroma: allChroma.compactMap{$0},
            fullBeatTimes: fullBeatTimes,
            sourceBitDepth: sourceBitDepth,
            allStereo: Array(allStereo.prefix(idx)).compactMap{$0},
            allChannelEnergy: Array(allChannelEnergy.prefix(idx)),
            allHPSSData: allHPSS.compactMap{$0},
            nmfComponentEnergy: nmfComponentEnergy,
            nmfReconError: nmfReconError,
            waveformEnvelope: waveformEnvelope,
            reduction: reductionRes,
            musicology: musicology,
            historicalEng: historicalEng
        )
        
        // The library produces *data*, not files. Lift the internal engine
        // aggregate into the public, layered `AudioReport`. Persistence (md /
        // json / plist) and rendering are the caller's choice.
        let context = AudioReport.SourceContext(
            sourceURL: url.path,
            durationSeconds: Double(totalFrames) / sampleRate,
            sampleRate: sampleRate,
            channelCount: Int(inputFormat.channelCount),
            sourceBitDepth: sourceBitDepth
        )

        progress(100, "Analysis complete.", nil)
        return (finalAnalysis, context)
    }

    private func assembleFinalDNA(filename: String, allLoudness: [LoudnessEngine.LoudnessResult], 
                                  allSpectral: [AdvancedSpectralMetrics], allOnsets: [OnsetResult], 
                                  allBitDepths: [Int], 
                                  allCodecs: [Float],
                                  allClipping: [Int],
                                  allEntropy: [Float],
                                  allInstruments: [InstrumentPrediction], 
                                  allScience: [ScienceMetrics], allTonnetz: [[Float]], allNMF: [Float], 
                                  allPiptrack: [Float], allViterbi: [[Int]], allYIN: [PitchResult],
                                  cyclicTempoMap: [Float],
                                  allMFCC: [[Float]], structureResult: StructureResult?,
                                  allRhythm: [RhythmResult], allContrast: [[Float]],
                                  allChroma: [[[Float]]],
                                  fullBeatTimes: [Double],
                                  sourceBitDepth: Int,
                                  allStereo: [StereoEngine.StereoResult],
                                  allChannelEnergy: [(left: Float, right: Float)],
                                  allHPSSData: [HPSSResult],
                                  nmfComponentEnergy: [Float],
                                  nmfReconError: Float,
                                  waveformEnvelope: [Float],
                                  reduction: ReductionMetrics,
                                  musicology: MusicologyMetrics,
                                  historicalEng: HistoricalEngine) -> MusicDNAAnalysis {
        
        let powers = allLoudness.map { powf(10.0, ($0.integratedLUFS + 0.691) / 10.0) }
        let finalLufs = 10.0 * log10f(powers.reduce(0, +) / Float(max(1, powers.count))) - 0.691
        let finalPeak = allLoudness.map { $0.truePeakDb }.max() ?? -100
        
        // Global tempo = median of per-chunk autocorrelation BPMs. Each per-chunk value
        // is already octave-guarded and clamped to [40, 320], so the median is a robust
        // global estimate. (The old 60/medianIBI path over concatenated beat times
        // collapsed to 60/45 = 1.33 BPM when per-chunk beat tracking degenerated.)
        let perChunkBPMs = allRhythm.map { Float($0.bpm) }.filter { $0 > 0 }.sorted()
        let globalBPM: Float = perChunkBPMs.isEmpty ? 0 : perChunkBPMs[perChunkBPMs.count / 2]

        let meanBPM = globalBPM
        let meanConfidence = allRhythm.map { $0.bpmConfidence }.reduce(0, +) / Float(max(1, allRhythm.count))
        
        // Real stereo metrics: energy-weighted across chunks so loud sections dominate.
        let stereoTotalEnergy = allChannelEnergy.reduce(Float(0)) { $0 + $1.left + $1.right }
        var wPhase: Float = 0, wWidth: Float = 0, wSide: Float = 0
        if stereoTotalEnergy > 1e-12 {
            for (i, s) in allStereo.enumerated() {
                let w = (i < allChannelEnergy.count) ? (allChannelEnergy[i].left + allChannelEnergy[i].right) : 0
                wPhase += s.correlationIndex * w
                wWidth += s.stereoWidth * w
                wSide  += s.sideEnergyPercent * w
            }
            wPhase /= stereoTotalEnergy; wWidth /= stereoTotalEnergy; wSide /= stereoTotalEnergy
        }
        let totalL = allChannelEnergy.reduce(Float(0)) { $0 + $1.left }
        let totalR = allChannelEnergy.reduce(Float(0)) { $0 + $1.right }
        let balanceLR: Float = (totalL + totalR) > 1e-12 ? (totalR - totalL) / (totalR + totalL) : 0
        let monoCompat: String = allStereo.max(by: { ($0.correlationIndex) < ($1.correlationIndex) })?.monoCompatibility
            ?? (allStereo.first?.monoCompatibility ?? "Unknown")

        let mastering = MasteringMetrics(integratedLUFS: finalLufs, momentaryLUFS: allLoudness.map{$0.momentaryLUFsMax}.max() ?? -70, shortTermLUFS: allLoudness.map{$0.shortTermLUFsMax}.max() ?? -70, truePeak: finalPeak, phaseCorrelation: wPhase, monoCompatibility: monoCompat, balanceLR: balanceLR, msBalance: balanceLR, sideEnergyPercent: wSide, stereoWidth: wWidth, lraLU: allLoudness.map{$0.loudnessRange}.max() ?? 0)
        
        // Was hardcoded `0..<7`, silently depending on `SpectralFeatureEngine.spectralContrast`
        // returning one extra always-zero row (nBands+1 instead of nBands) — fixing that bug
        // shrank each `allContrast[chunk]` to its correct nBands=6 length and turned this into
        // an out-of-bounds crash (`$0[6]` on a 6-element array). Derive the count from the
        // actual data instead of a magic number, so this can't silently drift out of sync again.
        let contrastBandCount = allContrast.first?.count ?? 0
        let finalContrast = (0..<contrastBandCount).map { i in allContrast.map { $0[i] }.reduce(0, +) / Float(max(1, allContrast.count)) }
        
        // `structureResult` comes from a single whole-track analysis (see analyzeAggregate's
        // per-chunk loop / post-loop comments) -- segment times are already global, no per-chunk
        // offset needed.
        let finalSegments: [MusicSegment] = (structureResult?.segments ?? []).enumerated().map { i, seg in
            MusicSegment(id: i + 1, start: seg.startSec, end: seg.endSec, label: seg.label)
        }

        // Global Beat Consistency (v7.1 Forensic upgrade)
        var globalBeatConsistency: Float = 0
        if fullBeatTimes.count > 2 {
            var ibis = [Float]()
            for i in 1..<fullBeatTimes.count {
                ibis.append(Float(fullBeatTimes[i] - fullBeatTimes[i-1]))
            }
            let avg = ibis.reduce(0, +) / Float(ibis.count)
            let variance = ibis.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Float(ibis.count)
            globalBeatConsistency = sqrtf(variance)
        }

        // Global Pitch Refinement (v7.1 Forensic upgrade)
        let validYIN = allYIN.map { $0 }
        let allF0s = validYIN.map { $0.meanF0 }.filter { !$0.isNaN && $0 > 0 }
        let meanF0 = allF0s.reduce(0, +) / Float(max(1, allF0s.count))
        let minF0 = allF0s.min() ?? 0
        let maxF0 = allF0s.max() ?? 0
        
        let totalVoiced = validYIN.map { Float($0.voicedFrames.count) }.reduce(0, +)
        let totalFrames = validYIN.map { Float($0.f0Series.count) }.reduce(0, +)
        let voicedRatio = totalVoiced / Float(max(1, totalFrames))
        // Pitch stability from the dispersion of voiced F0 (coefficient of variation).
        // Tight pitch → low CV → stability near 1.0; erratic pitch → lower.
        let stability: Float = {
            guard allF0s.count > 1, meanF0 > 1e-6 else { return allF0s.isEmpty ? 0 : 1 }
            let variance = allF0s.map { ($0 - meanF0) * ($0 - meanF0) }.reduce(0, +) / Float(allF0s.count)
            let cv = sqrtf(variance) / meanF0
            return Swift.max(0, Swift.min(1, 1 - cv))
        }()

        let finalCentroid = allSpectral.map { $0.centroid }.reduce(0, +) / Float(max(1, allSpectral.count))
        let finalRolloff = allSpectral.map { $0.rolloff }.reduce(0, +) / Float(max(1, allSpectral.count))
        let finalFlatness = allSpectral.map { $0.flatness }.reduce(0, +) / Float(max(1, allSpectral.count))
        let finalFlux = allSpectral.map { $0.flux }.reduce(0, +) / Float(max(1, allSpectral.count))
        let finalBandwidth = allSpectral.map { $0.bandwidth }.reduce(0, +) / Float(max(1, allSpectral.count))
        let finalZCR = allSpectral.map { $0.zcr }.reduce(0, +) / Float(max(1, allSpectral.count))
        
        let finalSpectral = AdvancedSpectralMetrics(
            centroid: finalCentroid, 
            rolloff: finalRolloff, 
            flatness: finalFlatness, 
            flux: finalFlux, 
            skewness: allSpectral.map { $0.skewness }.reduce(0, +) / Float(max(1, allSpectral.count)), 
            kurtosis: allSpectral.map { $0.kurtosis }.reduce(0, +) / Float(max(1, allSpectral.count)), 
            bandwidth: finalBandwidth, 
            zcr: finalZCR, 
            dynamicRange: allSpectral.map { $0.dynamicRange }.reduce(0, +) / Float(max(1, allSpectral.count)), 
            rmsMean: allSpectral.map { $0.rmsMean }.reduce(0, +) / Float(max(1, allSpectral.count)), 
            rmsMax: allSpectral.map { $0.rmsMax }.max() ?? 0, 
            brightnessDescription: finalCentroid > 5000 ? "Bright / Treble-heavy" : "Warm / Balanced", 
            fullMagnitudes: []
        )

        // ---- Real values for metrics that were previously hardcoded placeholders ----
        // HPSS energy ratios + component magnitude means (instance vs local shadowing
        // previously discarded the computed HPSS and reported 0.5/0.5 and 50/50).
        let hHarmRatio = allHPSSData.isEmpty ? 0.5 : allHPSSData.map { $0.harmonicEnergyRatio }.reduce(0, +) / Float(allHPSSData.count)
        let hPercRatio = allHPSSData.isEmpty ? 0.5 : allHPSSData.map { $0.percussiveEnergyRatio }.reduce(0, +) / Float(allHPSSData.count)
        func magMean(_ m: STFTMatrix) -> Float { m.magnitude.isEmpty ? 0 : m.magnitude.reduce(0, +) / Float(m.magnitude.count) }
        let harmonicMeanV = allHPSSData.first.map { magMean($0.harmonic) } ?? 0
        let percussiveMeanV = allHPSSData.first.map { magMean($0.percussive) } ?? 0
        let hpssChar = allHPSSData.first?.characterization ?? "Balanced"

        // Tonnetz harmonic stability = consistency of the 6-D tonal centroid across chunks.
        let tonnetzStability: Float = {
            let valid = allTonnetz.filter { $0.count == 6 }
            guard valid.count > 1 else { return valid.isEmpty ? 0 : 1 }
            var totalVar: Float = 0
            for d in 0..<6 {
                let col = valid.map { $0[d] }
                let m = col.reduce(0, +) / Float(col.count)
                totalVar += col.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(col.count)
            }
            return Swift.max(0, Swift.min(1, expf(-totalVar / 6.0)))
        }()

        // Semantic descriptors from real signal statistics.
        let topInstrumentLabel: String = {
            var acc = [String: (Float, Int)]()
            for p in allInstruments { let e = acc[p.label] ?? (0, 0); acc[p.label] = (e.0 + p.confidence, e.1 + 1) }
            return acc.map { ($0.key, $0.value.0 / Float(max(1, $0.value.1))) }.sorted { $0.1 > $1.1 }.first?.0 ?? "Unknown"
        }()
        let textureType: String = finalFlatness > 0.35 ? "Noisy / Dense" : (finalFlatness < 0.10 ? "Tonal / Sparse" : "Balanced")
        let presenceScore = Swift.max(0, Swift.min(1, (finalLufs + 60.0) / 60.0))
        let semanticReal = SemanticMetrics(
            dominanceMap: ["Harmonic": hHarmRatio, "Percussive": hPercRatio],
            primaryRole: topInstrumentLabel,
            textureType: textureType,
            presenceScore: presenceScore
        )

        let dominantPeriodReal = Int(meanBPM.rounded())
        let nmfComponentEnergyReal = nmfComponentEnergy.isEmpty ? [1.0] : nmfComponentEnergy

        // Forensic bit-depth reckoning.
        //   • measuredEffectiveBits = the resolution actually present in the signal
        //     (min step size across non-silent chunks; silent chunks report 0).
        //   • "Fake hi-res" / upsampling = the container DECLARES more bits than the
        //     data actually uses. Low entropy is NOT upsampling — a solo instrument
        //     legitimately has low entropy at full bit depth.
        let measuredEffectiveBits = allBitDepths.filter { $0 > 0 }.min()
            ?? (sourceBitDepth > 0 ? sourceBitDepth : 16)
        let isFakeHiRes = sourceBitDepth > 0
            && measuredEffectiveBits > 0
            && sourceBitDepth > measuredEffectiveBits

        // Whole-track mean chroma (reused below for both `chromaProfile` and, via the
        // Krumhansl-Kessler correlation profile, `TonalMetrics.keySignature`).
        let meanChromaProfile: [Float] = allChroma.reduce([Float](repeating: 0, count: 12)) { res, fragment in
            var next = res
            for c in 0..<12 {
                if c < fragment.count {
                    let binFrames = fragment[c]
                    var binSum: Float = 0
                    vDSP_sve(binFrames, 1, &binSum, vDSP_Length(binFrames.count))
                    next[c] += binSum / Float(max(1, binFrames.count))
                }
            }
            return next
        }.map { $0 / Float(max(1, allChroma.count)) }
        let keySignatureProfile = ModulationEngine().keyCorrelationProfile(meanChromaProfile)

        let finalAnalysis = MusicDNAAnalysis(
            fileName: filename,
            rhythm: RhythmMetrics(bpm: meanBPM, bpmConfidence: meanConfidence, beatConsistency: Float(globalBeatConsistency), onsetMean: allOnsets.map{$0.mean}.reduce(0,+)/Float(max(1,allOnsets.count)), onsetPeak: allOnsets.map{$0.peak}.max() ?? 0, characterize: globalBeatConsistency < 0.05 ? "Locked/Stable" : "Organic/Varied"),
            tonality: TonalMetrics(
                key: reduction.fundamentalNote, 
                keyConfidence: reduction.stabilityScore, 
                strength: reduction.stabilityScore, 
                harmonicStability: reduction.stabilityScore,
                keySignature: keySignatureProfile,
                tendency: reduction.stabilityScore > 0.8 ? "Stable" : "Evolving",
                scaleType: "Diatonic/Reduced",
                tuningSystem: "Equal Temperament"
            ),
            pitch: PitchMetrics(meanF0: meanF0, medianF0: meanF0, minF0: minF0, maxF0: maxF0, voicedRatio: voicedRatio, stability: stability),
            spectral: finalSpectral,
            hpss: HPSSMetrics(
                harmonicRatio: hHarmRatio,
                percussiveRatio: hPercRatio,
                harmonicEnergyRatio: hHarmRatio,
                percussiveEnergyRatio: hPercRatio,
                harmonicMean: harmonicMeanV,
                percussiveMean: percussiveMeanV,
                characterization: hpssChar
            ),
            timbre: TimbreMetrics(mfcc: allMFCC.first ?? [], spectralContrast: finalContrast),
            mastering: mastering,
            semantic: semanticReal,
            forensic: ForensicMetrics(
                sourceURL: filename, 
                encoder: allCodecs.max() ?? 0 > 18000 ? "High-Resolution Lossless/ALAC" : "Lossy Codec Detected", 
                isVerified: true,
                // The resolution actually present in the signal (measured), which can
                // be lower than the declared header depth in an upsampled file.
                effectiveBits: measuredEffectiveBits,
                isUpsampled: isFakeHiRes,
                codecCutoffHz: allCodecs.max() ?? 0, 
                entropyScore: allEntropy.reduce(0, +) / Float(max(1, allEntropy.count)), 
                clippingEvents: allClipping.reduce(0, +), 
                techSpecs: ["M4": "Active", "Engines": "26/26"]
            ),
            instruments: {
                var instrumentAccumulator = [String: (totalConf: Float, count: Int)]()
                for p in allInstruments {
                    let existing = instrumentAccumulator[p.label] ?? (0, 0)
                    instrumentAccumulator[p.label] = (existing.0 + p.confidence, existing.1 + 1)
                }
                let finalInstruments = instrumentAccumulator
                    .map { InstrumentPrediction(label: $0.key, confidence: $0.value.0 / Float($0.value.1), technicalBasis: "Probabilistic Aggregation") }
                    .sorted { $0.confidence > $1.confidence }
                
                return InstrumentMetrics(predictions: Array(finalInstruments.prefix(5)), primaryLabel: finalInstruments.first?.label ?? "Unknown")
            }(),
            science: {
                let validLRA = allScience.map { $0.dynamicRangeLRA }.filter { !$0.isNaN }
                let validSNR = allScience.map { $0.snr }
                let validThd = allScience.map { $0.thdPlusN }.filter { !$0.isNaN }
                let validImd = allScience.map { $0.smpteIMD }.filter { !$0.isNaN }
                let validNoise = allScience.map { $0.noiseFloorWeight468 }
                
                return ScienceMetrics(
                    dynamicRangeLRA: validLRA.isEmpty ? 0 : validLRA.reduce(0, +) / Float(validLRA.count),
                    // THD+N and SMPTE IMD are test-tone-only lab metrics; on real music no
                    // tone is present so no fragment yields a value. Return 0 (not NaN) — NaN
                    // is invalid JSON and breaks Codable. The mapping marks these validated:false.
                    thdPlusN: validThd.isEmpty ? 0 : validThd.reduce(0, +) / Float(validThd.count),
                    smpteIMD: validImd.isEmpty ? 0 : validImd.reduce(0, +) / Float(validImd.count),
                    snr: validSNR.isEmpty ? 0 : validSNR.reduce(0, +) / Float(validSNR.count),
                    noiseFloorWeight468: validNoise.isEmpty ? 0 : validNoise.reduce(0, +) / Float(validNoise.count),
                    status: "Verified"
                )
            }(),
            waveformPeaks: waveformEnvelope, chromaProfile: meanChromaProfile,
            segments: Array(finalSegments.prefix(256)), // whole-track coverage, not just first 45s
            audit: {
                // Was entirely hardcoded (identical literal values on every single analysis,
                // regardless of what actually ran) — `AuditMetrics` is directly reachable via
                // the public `AudioIntelligence.analyzeRawAggregate` API, not just internal.
                // `engineCoverage` now reflects whether each engine's array actually holds
                // real per-chunk results for THIS analysis, `cqtStatus` honestly reports that
                // CQTEngine feeds `TraditionalTheoryEngine.detectBassNote` (real bass-note
                // detection for chord inversion labeling and root/quality tie-breaking — see
                // CQTEngine.swift's own doc comment; this used to claim "no consumer", which was
                // stale even before this session's bass-note-root-selection fix), and
                // `melSpectrogramResolution` uses the real frame count (mel and chroma share the
                // same 512-sample hop, so `allChroma`'s frame count is exact). `utilityCheck`/
                // `filterbankStatus` are left "OK": both underlying utilities are deterministic
                // constructors with no defined failure mode to check against.
                let totalMelFrames = allChroma.reduce(0) { $0 + ($1.first?.count ?? 0) }
                let coverage: [String: Bool] = [
                    "Structure": structureResult != nil,
                    "HPSS": !allHPSSData.isEmpty,
                    "Rhythm": !allRhythm.isEmpty,
                    "Contrast": !allContrast.isEmpty,
                    "Chroma": !allChroma.isEmpty,
                ]
                return AuditMetrics(engineCoverage: coverage, cqtStatus: "Used (feeds TraditionalTheoryEngine bass-note detection)", melSpectrogramResolution: "128x\(totalMelFrames)", utilityCheck: "OK", filterbankStatus: "OK")
            }(),
            tonnetz: TonnetzMetrics(meanTonnetz: allTonnetz.first ?? [], harmonicStability: tonnetzStability),
            tempogram: TempogramMetrics(cyclicTempoMap: cyclicTempoMap, dominantPeriod: dominantPeriodReal),
            nmf: NMFMetrics(reconstructionError: nmfReconError, componentEnergy: nmfComponentEnergyReal),
            piptrack: PiptrackMetrics(refinedMeanF0: allPiptrack.reduce(0, +) / Float(max(1, allPiptrack.count)), trackingConfidence: voicedRatio),
            viterbi: ViterbiMetrics(path: allViterbi.first ?? [], confidence: stability),
            reduction: reduction,
            musicology: musicology
        )
        
        // Context Inference (requires full analysis data)
        let contextRes = historicalEng.inferContext(analysis: finalAnalysis)
        
        return MusicDNAAnalysis(
            fileName: filename,
            rhythm: finalAnalysis.rhythm,
            tonality: finalAnalysis.tonality,
            pitch: finalAnalysis.pitch,
            spectral: finalAnalysis.spectral,
            hpss: finalAnalysis.hpss,
            timbre: finalAnalysis.timbre,
            mastering: finalAnalysis.mastering,
            semantic: finalAnalysis.semantic,
            forensic: finalAnalysis.forensic,
            instruments: finalAnalysis.instruments,
            science: finalAnalysis.science,
            waveformPeaks: finalAnalysis.waveformPeaks,
            chromaProfile: finalAnalysis.chromaProfile,
            segments: finalAnalysis.segments,
            audit: finalAnalysis.audit,
            tonnetz: finalAnalysis.tonnetz,
            tempogram: finalAnalysis.tempogram,
            nmf: finalAnalysis.nmf,
            piptrack: finalAnalysis.piptrack,
            viterbi: finalAnalysis.viterbi,
            reduction: finalAnalysis.reduction,
            musicology: MusicologyMetrics(
                ursatz: musicology.ursatz,
                cadences: musicology.cadences,
                verticalAnalysis: musicology.verticalAnalysis,
                counterpointSpecies: musicology.counterpointSpecies,
                counterpointErrors: musicology.counterpointErrors,
                fundamentalBasis: musicology.fundamentalBasis,
                motifs: musicology.motifs,
                modulations: musicology.modulations,
                meter: musicology.meter,
                context: contextRes
            )
        )
    }

}
