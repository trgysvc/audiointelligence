import SwiftUI

/**
 * v6.0: Spectral Landscape View
 * A high-performance 3D-effect topography map of the audio spectrum.
 */
public struct SpectralLandscapeView: View {
    public let magnitudes: [[Float]] // [FrequencyBin][FrameIndex]
    
    public init(magnitudes: [[Float]]) {
        self.magnitudes = magnitudes
    }
    
    public var body: some View {
        Canvas { context, size in
            let nBins = magnitudes.count
            if nBins == 0 { return }
            let nFrames = magnitudes[0].count
            
            let spacingX = size.width / CGFloat(nFrames)
            let spacingY = size.height / CGFloat(nBins)
            
            // Perspective Projection Simulation
            for i in stride(from: 0, through: nBins - 1, by: 4) {
                var path = Path()
                let yPos = size.height - CGFloat(i) * spacingY
                
                for j in 0..<nFrames {
                    let mag = magnitudes[i][j]
                    let x = CGFloat(j) * spacingX
                    let y = yPos - CGFloat(mag * 100.0) // Peak height
                    
                    if j == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                context.stroke(path, with: .color(AITheme.Colors.accentCyan.opacity(0.3)), lineWidth: 1)
            }
        }
        .padding()
        .glassCard()
    }
}
