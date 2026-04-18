import Foundation
import Metal
import Accelerate

/**
 * AudioIntelligenceMetal - High Throughput Apple Silicon Acceleration
 * This version uses runtime compilation and specialized kernels for Streaming MIR.
 */
public final class MetalEngine: @unchecked Sendable {
    
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    
    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void calculate_squares(
        const device float* in [[ buffer(0) ]],
        device float* out [[ buffer(1) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        float sample = in[id];
        out[id] = sample * sample;
    }

    kernel void stress_test(
        const device float* in [[ buffer(0) ]],
        device float* out [[ buffer(1) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        float x = in[id];
        // Optimized for M4 Stability: Reduced iterations to prevent TDR timeout
        for(int i=0; i<32; i++) {
            x = sin(x) + cos(x);
        }
        out[id] = x;
    }

    kernel void batch_dct(
        const device float* in [[ buffer(0) ]],
        device float* out [[ buffer(1) ]],
        constant uint& n_mfcc [[ buffer(2) ]],
        constant uint& n_mels [[ buffer(3) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        uint frame_idx = id / n_mfcc;
        uint mfcc_idx = id % n_mfcc;
        
        float sum = 0.0;
        for (uint i = 0; i < n_mels; i++) {
            float val = in[frame_idx * n_mels + i];
            sum += val * cos(M_PI_F / (float)n_mels * (i + 0.5f) * (float)mfcc_idx);
        }
        // Scale for numerical stability
        out[id] = sum * sqrt(2.0f / (float)n_mels);
    }

    kernel void unified_forensic_kernel(
        const device float* magnitude [[ buffer(0) ]],
        device float* intensity [[ buffer(1) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        float mag = magnitude[id];
        
        // Stabilized Forensic Transform: prevent GPU hang
        float x = mag;
        for(int j=0; j<8; j++) {
            x = log(x + 1.0f) * sin(x);
        }
        intensity[id] = x;
    }
    """
    
    private var squareState: MTLComputePipelineState?
    private var stressState: MTLComputePipelineState?
    private var dctState: MTLComputePipelineState?
    private var forensicState: MTLComputePipelineState?
    
    public init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
        
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let device = device else { return }
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            if let squareFunc = library.makeFunction(name: "calculate_squares") {
                self.squareState = try device.makeComputePipelineState(function: squareFunc)
            }
            if let stressFunc = library.makeFunction(name: "stress_test") {
                self.stressState = try device.makeComputePipelineState(function: stressFunc)
            }
            if let dctFunc = library.makeFunction(name: "batch_dct") {
                self.dctState = try device.makeComputePipelineState(function: dctFunc)
            }
            if let forensicFunc = library.makeFunction(name: "unified_forensic_kernel") {
                self.forensicState = try device.makeComputePipelineState(function: forensicFunc)
            }
        } catch {
            print("⚠️ Metal Engine: Runtime compilation failed - \(error.localizedDescription)")
        }
    }
    
    public func executeUnifiedForensicTransform(magnitude: [Float]) -> [Float] {
        guard let device = device, let commandQueue = commandQueue, let forensicState = forensicState, !magnitude.isEmpty else {
            return []
        }
        
        let count = magnitude.count
        let size = count * MemoryLayout<Float>.stride
        
        // Memory Protection: Limit max buffer size to prevent allocation failures
        guard size < device.maxBufferLength else { return [] }
        
        guard let magBuffer = device.makeBuffer(bytes: magnitude, length: size, options: .storageModeShared),
              let intBuffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            return []
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }
        
        encoder.setComputePipelineState(forensicState)
        encoder.setBuffer(magBuffer, offset: 0, index: 0)
        encoder.setBuffer(intBuffer, offset: 0, index: 1)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = forensicState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let intPtr = intBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: intPtr, count: count))
    }
    
    public func runDiagnosticStressTest() async {
        guard let device = device, let commandQueue = commandQueue, let stressState = stressState else { return }
        
        let count = 1_000_000 // Safer count
        let inBuffer = device.makeBuffer(length: count * 4, options: .storageModeShared)
        let outBuffer = device.makeBuffer(length: count * 4, options: .storageModeShared)
        
        if inBuffer == nil || outBuffer == nil { return }
        
        for _ in 0..<3 { 
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
            
            encoder.setComputePipelineState(stressState)
            encoder.setBuffer(inBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
            
            let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
            let w = stressState.threadExecutionWidth
            let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
            
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
            
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                commandBuffer.addCompletedHandler { _ in
                    continuation.resume()
                }
                commandBuffer.commit()
            }
        }
    }
    
    public func executeParallelSquaring(samples: [Float]) -> [Float] {
        guard let device = device, let commandQueue = commandQueue, let squareState = squareState, !samples.isEmpty else {
            return samples.map { $0 * $0 }
        }
        
        let count = samples.count
        let size = count * MemoryLayout<Float>.stride
        
        guard let inBuffer = device.makeBuffer(bytes: samples, length: size, options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            return samples.map { $0 * $0 }
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return samples.map { $0 * $0 }
        }
        
        encoder.setComputePipelineState(squareState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = squareState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted() // Synchronous path for non-async calls
        
        let pointer = outBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    public func executeBatchDct(melSpectrogram: [Float], nMfcc: Int, nMels: Int) -> [Float] {
        guard let device = device, let commandQueue = commandQueue, let dctState = dctState, !melSpectrogram.isEmpty else {
            return []
        }
        
        let nFrames = melSpectrogram.count / nMels
        let count = nFrames * nMfcc
        
        guard let inBuffer = device.makeBuffer(bytes: melSpectrogram, length: melSpectrogram.count * 4, options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: count * 4, options: .storageModeShared) else {
            return []
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }
        
        encoder.setComputePipelineState(dctState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        var uintMfcc = UInt32(nMfcc); var uintMels = UInt32(nMels)
        encoder.setBytes(&uintMfcc, length: 4, index: 2)
        encoder.setBytes(&uintMels, length: 4, index: 3)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = dctState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let pointer = outBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    public func getHardwareStatus() -> String {
        guard let device = device else { return "None (Metal No Supported)" }
        return device.name
    }
}
