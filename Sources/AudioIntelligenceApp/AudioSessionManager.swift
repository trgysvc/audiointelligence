import SwiftUI
import AudioIntelligence

/**
 * v6.1: Audio Session Manager
 * Reactive state management for the AudioIntelligence application.
 */
@MainActor
public final class AudioSessionManager: ObservableObject {
    
    @Published public var isAnalyzing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = ""
    @Published public var currentAnalysis: MusicDNAAnalysis?
    
    private let metalEngine = MetalEngine()
    private lazy var builder = DNAReportBuilder(metalEngine: metalEngine)
    
    public init() {}
    
    public func analyzeFile(at url: URL) async {
        isAnalyzing = true
        progress = 0
        statusMessage = "Initializing Analysis Engine..."
        
        do {
            let result = try await builder.analyze(url: url) { p, msg, _ in
                Task { @MainActor in
                    self.progress = p
                    self.statusMessage = msg
                }
            }
            
            withAnimation(.spring()) {
                self.currentAnalysis = result.analysis
                self.isAnalyzing = false
            }
        } catch {
            self.statusMessage = "Error: \(error.localizedDescription)"
            self.isAnalyzing = false
        }
    }
    
    public func reset() {
        withAnimation {
            self.currentAnalysis = nil
            self.progress = 0
            self.statusMessage = ""
        }
    }
}
