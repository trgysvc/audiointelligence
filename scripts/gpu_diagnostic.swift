import Foundation
import Metal
import Accelerate

/**
 * GPU Stress Test & Diagnostic Tool
 * Used to verify Metal kernel execution and trigger visible GPU usage in Activity Monitor.
 */

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

kernel void stress_test(
    const device float* in [[ buffer(0) ]],
    device float* out [[ buffer(1) ]],
    uint id [[ thread_position_in_grid ]]
) {
    float x = in[id];
    // Artificial heavy workload to keep GPU busy
    for(int i=0; i<500; i++) {
        x = sin(x) + cos(x);
    }
    out[id] = x;
}
"""

print("🔍 GPU Diagnostic Başlatılıyor...")

guard let device = MTLCreateSystemDefaultDevice() else {
    print("❌ HATA: Metal destekleyen GPU bulunamadı.")
    exit(1)
}

print("✅ GPU Bulundu: \(device.name)")

do {
    let library = try device.makeLibrary(source: shaderSource, options: nil)
    guard let function = library.makeFunction(name: "stress_test") else {
        print("❌ HATA: Shader fonksiyonu bulunamadı.")
        exit(1)
    }
    
    let pipelineState = try device.makeComputePipelineState(function: function)
    let commandQueue = device.makeCommandQueue()!
    
    func runDiagnostic() async {
    print("🚀 Initializing M4 Silicon GPU Stress Test...")
    let metal = MetalEngine()
    print("🎯 Hardware Target: \(metal.getHardwareStatus())")
    
    let inputData = [Float](repeating: 1.0, count: 1_000_000)
    let squared = metal.executeParallelSquaring(samples: inputData)
    print("✅ Parallel Squaring Test: \(squared.prefix(5))...")
    
    print("🔥 Starting Stress Loop (Unified Pipeline)...")
    await metal.runDiagnosticStressTest()
    print("🏁 Stress Test Complete. M4 Silicon ALIGNED.")
}

await runDiagnostic()
    
    let count = 10_000_000 // 10M samples
    let size = count * MemoryLayout<Float>.stride
    
    var inputData = [Float](repeating: 1.0, count: count)
    let inBuffer = device.makeBuffer(bytes: inputData, length: size, options: .storageModeShared)!
    let outBuffer = device.makeBuffer(length: size, options: .storageModeShared)!
    
    print("🚀 GPU Yoğun İşlem Başlatılıyor (10M samples, 500 iterations)...")
    print("📊 Lütfen Activity Monitor'deki GPU sütununu kontrol edin.")
    
    let startTime = CFAbsoluteTimeGetCurrent()
    
    for iteration in 1...5 {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        
        let w = pipelineState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        print("⏳ Iterasyon \(iteration)/5 tamamlandı.")
    }
    
    let duration = CFAbsoluteTimeGetCurrent() - startTime
    print("✨ Diagnostic Tamamlandı. Toplam Süre: \(duration) saniye.")
    
} catch {
    print("❌ Metal Hatası: \(error)")
}
