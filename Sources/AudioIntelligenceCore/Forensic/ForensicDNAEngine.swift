// ForensicDNAEngine.swift
// Elite Music DNA Engine — Phase 4
//
// "Audit" Forensic Analysis.
// Traces file provenance, encoding details, and system metadata.

import Foundation

public struct ForensicDNA: Sendable {
    public let metadata: [String: String]
    public let provenance: [String: String] // mdls results (WhereFroms, etc)
    public let signatures: [String]          // LAME, iTunes, etc
    public let techSpecs: [String: String]  // afinfo results
    public let effectiveBits: Int           // v25.0: 16 or 24
    public let isLikelyUpsampled: Bool       // v25.0: Entropy check
    
    public var whereFroms: [String] {
        provenance["Source"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .init(charactersIn: " () \"")) } ?? []
    }
    
    public var encoder: String {
        signatures.first ?? metadata["encoder"] ?? "Unknown"
    }
    
    public var signatureFound: Bool {
        !signatures.isEmpty
    }
    
    public var format: String {
        metadata["File Format"] ?? "Unknown"
    }
    
    public var bitRate: String {
        metadata["Bit Rate"] ?? "Unknown"
    }
}

public final class ForensicDNAEngine: Sendable {
    
    public init() {}
    
    /// Performs deep forensic analysis of an audio file.
    /// - Parameter url: Local URL to the audio file.
    /// - Parameter samples: PCM samples for entropy analysis.
    public func scan(at url: URL, samples: [Float]) async -> ForensicDNA {
        let techSpecs = await runShellCommand("/usr/bin/afinfo", [url.path])
        let provenance = await runShellCommand("/usr/bin/mdls", [url.path])
        
        let signatures = scanForSignatures(at: url)
        let bitDepth = analyzeBitDepthIntegrity(samples: samples)
        
        return ForensicDNA(
            metadata: parseTechnicalSpecs(techSpecs),
            provenance: parseProvenance(provenance),
            signatures: signatures,
            techSpecs: parseTechnicalSpecs(techSpecs),
            effectiveBits: bitDepth.effectiveBits,
            isLikelyUpsampled: bitDepth.isLikelyUpsampled
        )
    }
    
    // MARK: - Shell Command Runner
    
    private func runShellCommand(_ path: String, _ arguments: [String]) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Parsing
    
    private func parseTechnicalSpecs(_ input: String) -> [String: String] {
        var results: [String: String] = [:]
        let lines = input.components(separatedBy: .newlines)
        
        for line in lines {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                results[key] = value
            }
        }
        return results
    }
    
    private func parseProvenance(_ input: String) -> [String: String] {
        var results: [String: String] = [:]
        let lines = input.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("kMDItemWhereFroms") {
                results["Source"] = line.replacingOccurrences(of: "kMDItemWhereFroms =", with: "").trimmingCharacters(in: .whitespaces)
            }
            if line.contains("kMDItemDateAdded") {
                results["AddedDate"] = line.replacingOccurrences(of: "kMDItemDateAdded =", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return results
    }
    
    // MARK: - Information Entropy (Bit-Depth Integrity)
    
    /// Analyzes if a file claiming higher bit depth actually contains that much information.
    /// Detects 'Fake Hi-Res' (Upsampled 16-bit to 24-bit).
    public func analyzeBitDepthIntegrity(samples: [Float]) -> (isLikelyUpsampled: Bool, effectiveBits: Int) {
        // v51.0: Professional Entropy Analysis
        // We calculate the Shannon Entropy of the LSBs to distinguish between 
        // real 24-bit noise/detail and zero-padded 16-bit audio.
        
        let sampleCount = min(samples.count, 88200) // 2 seconds for better stat confidence
        var binCounts = [Int](repeating: 0, count: 256) // 8-bit LSB distribution
        
        for i in 0..<sampleCount {
            // Convert to 24-bit integer space
            let s = Int32(clamp(samples[i], min: -1.0, max: 1.0) * 8388607)
            let lsb = Int(s & 0xFF)
            binCounts[lsb] += 1
        }
        
        // Calculate Shannon Entropy: H = -sum(p * log2(p))
        var entropy: Float = 0
        for count in binCounts {
            if count > 0 {
                let p = Float(count) / Float(sampleCount)
                entropy -= p * (logf(p) / logf(2.0))
            }
        }
        
        // 16-bit upsampled to 24-bit will have near-zero LSB entropy (0-1 bits)
        // Real 24-bit audio will have high LSB entropy (6-8 bits)
        let isUpsampled = entropy < 3.0
        let effectiveBits = isUpsampled ? 16 : 24
        
        return (isUpsampled, effectiveBits)
    }
    
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        return Swift.max(min, Swift.min(max, value))
    }

    // MARK: - Binary Header Signature Search (Restored)
    
    private func scanForSignatures(at url: URL) -> [String] {
        var results: [String] = []
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            let data = fileHandle.readData(ofLength: 8192)
            let headerString = String(data: data, encoding: .ascii) ?? ""
            if headerString.contains("LAME") { results.append("LAME Encoder Detected") }
            if headerString.contains("Lavf") { results.append("FFmpeg (libavformat) Signature") }
            if headerString.contains("FhG")  { results.append("Fraunhofer IIS Encoder") }
            if headerString.contains("iTunes") { results.append("Apple iTunes Signature") }
            try fileHandle.close()
        } catch {}
        return results
    }
}
