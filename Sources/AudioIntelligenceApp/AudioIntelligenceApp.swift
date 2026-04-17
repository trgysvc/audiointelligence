import SwiftUI
import AudioIntelligenceUI
import AudioIntelligence

/**
 * v6.0: AudioIntelligence Application Entry Point
 * Premium standalone macOS Forensic Engine.
 */
@main
struct AudioIntelligenceApp: App {
    
    @StateObject private var session = AudioSessionManager()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                AITheme.Colors.background.ignoresSafeArea()
                
                if let analysis = session.currentAnalysis {
                    MainDashboardView(analysis: analysis)
                } else {
                    landingView
                }
                
                if session.isAnalyzing {
                    loadingOverlay
                }
            }
            .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
    
    private var landingView: some View {
        VStack(spacing: 30) {
            Image(systemName: "waveform.path.badge.plus")
                .font(.system(size: 80, weight: .thin))
                .foregroundColor(AITheme.Colors.accentCyan)
            
            VStack(spacing: 8) {
                Text("AudioIntelligence v6.1")
                    .font(AITheme.Typography.headline(24))
                Text("Premium Forensic Design & Engineering")
                    .font(AITheme.Typography.caption())
                    .foregroundColor(AITheme.Colors.mutedText)
            }
            
            Button(action: selectFile) {
                Text("Select Audio for DNA Audit")
                    .font(AITheme.Typography.headline(16))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AITheme.Colors.accentCyan)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: session.progress, total: 100)
                    .progressViewStyle(.circular)
                    .tint(AITheme.Colors.accentCyan)
                
                Text(session.statusMessage)
                    .font(AITheme.Typography.monoData(12))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                Task {
                    await session.analyzeFile(at: url)
                }
            }
        }
    }
}
