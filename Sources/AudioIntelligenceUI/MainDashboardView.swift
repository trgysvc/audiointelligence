import SwiftUI
import AudioIntelligence

/**
 * v6.0: Main Dashboard Interface
 * The premium, standalone "Engineering Station" dashboard.
 */
public struct MainDashboardView: View {
    let report: AudioReport

    public init(report: AudioReport) {
        self.report = report
    }

    private func fmt(_ v: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", v) }
    
    public var body: some View {
        NavigationSplitView {
            // HIG: Sidebar for session management
            List {
                Section("Recent Audits") {
                    Label(report.metadata.fileName, systemImage: "waveform.path")
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
                            InstrumentDNARing(dominanceMap: [
                                "Harmonic": Float(report.measurements.separation.harmonicRatio.value),
                                "Percussive": Float(report.measurements.separation.percussiveRatio.value)
                            ])
                        }
                        .padding()
                        .glassCard()
                        
                        // 2. Meters Card
                        VStack(alignment: .leading, spacing: 15) {
                            Text("FORENSIC METRICS")
                                .font(AITheme.Typography.headline())
                                .foregroundColor(AITheme.Colors.accentOrange)
                            
                            MetricRow(label: "Integrated LUFS", value: fmt(report.measurements.loudness.integrated.value, 1), unit: "LUFS")
                            MetricRow(label: "True Peak", value: fmt(report.measurements.loudness.truePeak.value, 1), unit: "dBTP")
                            MetricRow(label: "Correlation", value: fmt(report.measurements.stereo.phaseCorrelation.value, 3), unit: "Indx")
                            MetricRow(label: "Bit Depth", value: "\(report.measurements.forensic.effectiveBits.value)", unit: "bits")
                        }
                        .padding()
                        .glassCard()
                    }
                    
                    // 3. Spectral Landscape (Full Width)
                    VStack(alignment: .leading) {
                        Text("3D SPECTRAL TOPOGRAPHY")
                            .font(AITheme.Typography.headline())
                            .foregroundColor(.white)
                        SpectralLandscapeView(magnitudes: report.features?.magnitudeSpectrogram ?? [])
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
                Text(report.metadata.fileName)
                    .font(AITheme.Typography.headline(32))
                Text("AudioIntelligence \(report.libraryVersion) · schema \(report.schemaVersion)")
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
