import Foundation
import Metal

/**
 * v53.4: High-Performance Metal Engine (Runtime-Compiled)
 * Specifically optimized for Apple M-series Unified Memory Architecture.
 * This version uses runtime compilation to avoid SPM resource/bundle issues.
 */
public final class MetalEngine: @unchecked Sendable {
    
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    
    private var squareState: MTLComputePipelineState?
    private var reductionState: MTLComputePipelineState?
    
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

    kernel void parallel_reduction(
        const device float* in [[ buffer(0) ]],
        device float* out [[ buffer(1) ]],
        constant uint& count [[ buffer(2) ]],
        threadgroup float* shared_data [[ threadgroup(0) ]],
        uint tid [[ thread_index_in_threadgroup ]],
        uint bid [[ threadgroup_position_in_grid ]],
        uint bdim [[ threads_per_threadgroup ]]
    ) {
        uint gid = bid * bdim + tid;
        shared_data[tid] = (gid < count) ? in[gid] : 0.0f;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint s = bdim / 2; s > 0; s >>= 1) {
            if (tid < s) {
                shared_data[tid] += shared_data[tid + s];
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) {
            out[bid] = shared_data[0];
        }
    }
    """
    
    public init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
        
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let device = device else { return }
        
        // v53.4 Runtime Compilation: Bypassing SPM metallib issues
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            if let squareFunc = library.makeFunction(name: "calculate_squares"),
               let reductionFunc = library.makeFunction(name: "parallel_reduction") {
                self.squareState = try device.makeComputePipelineState(function: squareFunc)
                self.reductionState = try device.makeComputePipelineState(function: reductionFunc)
            }
        } catch {
            print("⚠️ Metal Engine: Runtime compilation failed - \(error.localizedDescription)")
        }
    }
    
    /// Verifies if Metal hardware is active and accessible.
    public func getHardwareStatus() -> String {
        guard let device = device else { return "None (Metal No Supported)" }
        let engineStatus = (squareState != nil) ? "Turbo (Kernels Active)" : "Basic (Buffer Only)"
        return "\(device.name) | \(engineStatus)"
    }
    
    public func executeParallelPower(samples: [Float]) -> Float {
        guard let device = device, 
              let commandQueue = commandQueue,
              let squareState = squareState,
              let reductionState = reductionState,
              !samples.isEmpty else {
            return 0.0
        }
        
        let count = samples.count
        let size = count * MemoryLayout<Float>.stride
        
        guard let inBuffer = device.makeBuffer(bytes: samples, length: size, options: .storageModeShared),
              let squareBuffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            return 0.0
        }
        
        let threadGroupSize = squareState.maxTotalThreadsPerThreadgroup
        let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)
        let groupsPerGrid = MTLSize(width: (count + threadGroupSize - 1) / threadGroupSize, height: 1, depth: 1)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return 0.0
        }
        
        encoder.setComputePipelineState(squareState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(squareBuffer, offset: 0, index: 1)
        encoder.dispatchThreadgroups(groupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        let numThreadgroups = groupsPerGrid.width
        let partialSumSize = numThreadgroups * MemoryLayout<Float>.stride
        guard let outBuffer = device.makeBuffer(length: partialSumSize, options: .storageModeShared),
              let redEncoder = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.commit()
            return 0.0
        }
        
        redEncoder.setComputePipelineState(reductionState)
        redEncoder.setBuffer(squareBuffer, offset: 0, index: 0)
        redEncoder.setBuffer(outBuffer, offset: 0, index: 1)
        var uintCount = UInt32(count)
        redEncoder.setBytes(&uintCount, length: MemoryLayout<UInt32>.size, index: 2)
        redEncoder.setThreadgroupMemoryLength(threadGroupSize * MemoryLayout<Float>.stride, index: 0)
        
        redEncoder.dispatchThreadgroups(groupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        redEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let pointer = outBuffer.contents().bindMemory(to: Float.self, capacity: numThreadgroups)
        var totalPower: Float = 0
        for i in 0..<numThreadgroups {
            totalPower += pointer[i]
        }
        
        return totalPower
    }
}
