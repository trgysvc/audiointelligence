import SwiftUI
import AudioIntelligence

/**
 * v6.0: Main Dashboard Interface
 * The premium, standalone "Engineering Station" dashboard.
 */
public struct MainDashboardView: View {
    let analysis: MusicDNAAnalysis
    
    public init(analysis: MusicDNAAnalysis) {
        self.analysis = analysis
    }
    
    public var body: some View {
        NavigationSplitView {
            // HIG: Sidebar for session management
            List {
                Section("Recent Audits") {
                    Label(analysis.fileName, systemImage: "waveform.path")
                        .font(AITheme.Typography.caption())
                }
            }
            .navigationTitle("Archive")
        } detail: {
            // HIG: Main Detail Area (The Dashboard)
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    
                    // Main Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        
                        // 1. Instrument DNA Card
                        VStack(alignment: .leading) {
                            Text("INSTRUMENT DNA")
                                .font(AITheme.Typography.headline())
                                .foregroundColor(AITheme.Colors.accentCyan)
                            InstrumentDNARing(dominanceMap: analysis.semantic.dominanceMap)
                        }
                        .padding()
                        .glassCard()
                        
                        // 2. Meters Card
                        VStack(alignment: .leading, spacing: 15) {
                            Text("FORENSIC METRICS")
                                .font(AITheme.Typography.headline())
                                .foregroundColor(AITheme.Colors.accentOrange)
                            
                            MetricRow(label: "Integrated LUFS", value: "\(analysis.mastering.integratedLUFS)", unit: "LUFS")
                            MetricRow(label: "True Peak", value: "\(analysis.mastering.truePeak)", unit: "dBTP")
                            MetricRow(label: "Correlation", value: "\(analysis.mastering.phaseCorrelation)", unit: "Indx")
                            MetricRow(label: "Bit Depth", value: "\(analysis.forensic.effectiveBits)", unit: "bits")
                        }
                        .padding()
                        .glassCard()
                    }
                    
                    // 3. Spectral Landscape (Full Width)
                    VStack(alignment: .leading) {
                        Text("3D SPECTRAL TOPOGRAPHY")
                            .font(AITheme.Typography.headline())
                            .foregroundColor(.white)
                        SpectralLandscapeView(magnitudes: [[0.1, 0.2, 0.5]]) // Placeholder data
                            .frame(height: 300)
                    }
                }
                .padding()
            }
            .background(AITheme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {}) {
                        Label("Analyze", systemImage: "play.fill")
                    }
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(analysis.fileName)
                    .font(AITheme.Typography.headline(32))
                Text("v56.0 Forensic Audit | Apple M4 Accelerated")
                    .font(AITheme.Typography.caption())
                    .foregroundColor(AITheme.Colors.mutedText)
            }
            Spacer()
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    let unit: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(AITheme.Typography.caption())
                .foregroundColor(AITheme.Colors.mutedText)
            Spacer()
            Text(value)
                .font(AITheme.Typography.monoData())
                .foregroundColor(.white)
            Text(unit)
                .font(AITheme.Typography.caption(10))
                .foregroundColor(AITheme.Colors.accentCyan)
        }
        Divider().background(Color.white.opacity(0.1))
    }
}
