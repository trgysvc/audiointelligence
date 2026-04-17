import Foundation
import AudioIntelligenceCore

let engine = CQTEngine(sampleRate: 22050)
let samples = [Float](repeating: 0.1, count: 1000)
print("Starting CQT Transfrom...")
let result = engine.transform(samples)
print("CQT Transform Success! Result bins: \(result.count)")
