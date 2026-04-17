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
            
            let spacingX = size.width / CGFloat(max(1, nFrames - 1))
            let spacingY = size.height / CGFloat(max(1, nBins / 4)) // Skip bins for performance
            
            context.withCGContext { cgContext in
                cgContext.setLineWidth(1.0)
                cgContext.setLineCap(.round)
                
                // Render from back to front for "landscape" effect
                for i in stride(from: nBins - 1, through: 0, by: -16) {
                    var path = Path()
                    let depthOffset = CGFloat(i) * 0.5 // Simulated perspective
                    let yOrigin = size.height - CGFloat(i / 16) * spacingY
                    
                    for j in stride(from: 0, to: nFrames, by: 4) {
                        let mag = magnitudes[i][j]
                        let x = CGFloat(j) * spacingX + depthOffset
                        let y = yOrigin - CGFloat(mag * 150.0) // Sensitivity scaling
                        
                        if j == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    
                    // HIG: Dynamic Color Coding
                    let color = i < nBins / 4 ? AITheme.Colors.accentOrange : AITheme.Colors.accentCyan
                    context.stroke(path, with: .color(color.opacity(0.4)), lineWidth: 0.8)
                }
            }
        }
        .padding()
        .glassCard()
    }
}
