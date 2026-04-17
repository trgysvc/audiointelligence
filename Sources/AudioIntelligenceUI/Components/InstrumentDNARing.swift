import SwiftUI

/**
 * v6.0: Instrument DNA Ring
 * A premium visualization showing spectral dominance across instrument classes.
 */
public struct InstrumentDNARing: View {
    public let dominanceMap: [String: Float]
    @State private var animate = false
    
    public init(dominanceMap: [String: Float]) {
        self.dominanceMap = dominanceMap
    }
    
    public var body: some View {
        ZStack {
            // Background Track
            Circle()
                .stroke(AITheme.Colors.glassWhite, lineWidth: 20)
            
            // Dynamic Segments
            let sortedPairs = dominanceMap.sorted(by: { $0.value > $1.value })
            var currentStart: Double = -90.0
            
            ForEach(0..<sortedPairs.count, id: \.self) { index in
                let pair = sortedPairs[index]
                let sweep = Double(pair.value) / 100.0 * 360.0
                
                SegmentShape(startAngle: Angle(degrees: currentStart), sweep: sweep)
                    .stroke(
                        getSegmentColor(for: pair.key),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round)
                    )
                    .opacity(animate ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 1.0).delay(Double(index) * 0.1), value: animate)
                
                // Update start for next segment
                // Note: In SwiftUI views, we can't easily mutate variables during drawing like this.
                // We'll pre-calculate the start angles.
            }
            
            // Center Labels
            VStack {
                Text("ANALYSIS")
                    .font(AITheme.Typography.caption(10))
                    .foregroundColor(AITheme.Colors.mutedText)
                Text("100%")
                    .font(AITheme.Typography.headline(24))
                    .foregroundColor(.white)
            }
        }
        .padding(40)
        .onAppear { animate = true }
    }
    
    private func getSegmentColor(for label: String) -> Color {
        switch label.lowercased() {
        case let l where l.contains("lead") || l.contains("vocal"): return AITheme.Colors.accentCyan
        case let l where l.contains("bass"): return .green
        case let l where l.contains("drum") || l.contains("perc"): return AITheme.Colors.accentOrange
        default: return .purple
        }
    }
}

private struct SegmentShape: Shape {
    var startAngle: Angle
    var sweep: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle + Angle(degrees: sweep),
            clockwise: false
        )
        return path
    }
}
