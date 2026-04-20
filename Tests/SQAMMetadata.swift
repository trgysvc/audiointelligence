import Foundation

/// Reference metadata for the 70 SQAM tracks to verify AudioIntelligence accuracy.
struct SQAMReference: Codable, Sendable {
    let track: String
    let description: String
    let category: String
    let expectedInstrument: String?
    let expectedKey: String? // If applicable
    let purpose: String
}

let sqamGroundTruth: [SQAMReference] = [
    // --- Technical Signals ---
    SQAMReference(track: "01", description: "Sine wave, 1 kHz", category: "Technical", expectedInstrument: nil, expectedKey: "C", purpose: "Level & Frequency Accuracy"),
    SQAMReference(track: "03", description: "Electronic gong, 100 Hz", category: "Technical", expectedInstrument: nil, expectedKey: nil, purpose: "LF Response"),
    SQAMReference(track: "07", description: "Electronic tune (Frere Jacques)", category: "Technical", expectedInstrument: "Synthesizer", expectedKey: "F", purpose: "Pitch Tracking"),
    
    // --- Solo Instruments ---
    SQAMReference(track: "08", description: "Violin", category: "Solo", expectedInstrument: "Violin", expectedKey: nil, purpose: "Timbral Fidelity"),
    SQAMReference(track: "09", description: "Viola", category: "Solo", expectedInstrument: "Viola", expectedKey: nil, purpose: "Mid-Range Accuracy"),
    SQAMReference(track: "10", description: "Violoncello", category: "Solo", expectedInstrument: "Cello", expectedKey: nil, purpose: "LF String Detail"),
    SQAMReference(track: "11", description: "Contrabass", category: "Solo", expectedInstrument: "Double Bass", expectedKey: nil, purpose: "Sub-harmonic Accuracy"),
    
    SQAMReference(track: "21", description: "Trumpet", category: "Solo", expectedInstrument: "Trumpet", expectedKey: "Bb", purpose: "Transient & Harmonic Accuracy"),
    SQAMReference(track: "22", description: "Trombone", category: "Solo", expectedInstrument: "Trombone", expectedKey: nil, purpose: "Brass Timbre"),
    SQAMReference(track: "23", description: "French Horn", category: "Solo", expectedInstrument: "Horn", expectedKey: nil, purpose: "Mid-harmonic Warmth"),
    SQAMReference(track: "26", description: "Oboe", category: "Solo", expectedInstrument: "Oboe", expectedKey: nil, purpose: "Harmonic Purity"),
    SQAMReference(track: "27", description: "Clarinet", category: "Solo", expectedInstrument: "Clarinet", expectedKey: nil, purpose: "Spectral Balance"),
    SQAMReference(track: "29", description: "Piano", category: "Solo", expectedInstrument: "Piano", expectedKey: nil, purpose: "Wideband Frequency Accuracy"),
    SQAMReference(track: "35", description: "Glockenspiel", category: "Solo", expectedInstrument: "Glockenspiel", expectedKey: nil, purpose: "HF Transient Precision"),
    SQAMReference(track: "40", description: "Harpsichord", category: "Solo", expectedInstrument: "Harpsichord", expectedKey: nil, purpose: "Transient Richness"),
    SQAMReference(track: "42", description: "Accordion", category: "Solo", expectedInstrument: "Accordion", expectedKey: nil, purpose: "Complex Spectrum"),
    SQAMReference(track: "43", description: "Harp", category: "Solo", expectedInstrument: "Harp", expectedKey: nil, purpose: "Isolated Transient Tracking"),

    // --- Vocal ---
    SQAMReference(track: "44", description: "Soprano", category: "Vocal", expectedInstrument: "Voice (Female)", expectedKey: nil, purpose: "Vocal Formants"),
    SQAMReference(track: "47", description: "Bass", category: "Vocal", expectedInstrument: "Voice (Male)", expectedKey: nil, purpose: "Low-frequency Formants"),
    SQAMReference(track: "48", description: "Quartet", category: "Vocal", expectedInstrument: "Vocal Ensemble", expectedKey: nil, purpose: "Choral Separation"),

    // --- Complex / Orchestral ---
    SQAMReference(track: "61", description: "Orchestra (Tchaikovsky)", category: "Orchestral", expectedInstrument: "Full Orchestra", expectedKey: nil, purpose: "Spectral Breadth"),
    SQAMReference(track: "65", description: "Pop (Fast)", category: "Pop", expectedInstrument: "Full Band", expectedKey: nil, purpose: "Dynamics & Pulse Tracking"),
    SQAMReference(track: "70", description: "Speech (Male)", category: "Speech", expectedInstrument: "Voice (Male)", expectedKey: nil, purpose: "Transient Speech Fidelity")
]
