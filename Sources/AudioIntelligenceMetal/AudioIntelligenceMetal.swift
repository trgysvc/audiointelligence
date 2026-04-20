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
    
    /// telemetry for verifying GPU engagement in unit tests
    public private(set) var kernelExecutionCount: [String: Int] = [:]
    
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

    kernel void median_filter_2d(
        const device float* in [[ buffer(0) ]],
        device float* out [[ buffer(1) ]],
        constant uint& n_rows [[ buffer(2) ]],
        constant uint& n_cols [[ buffer(3) ]],
        constant uint& window_size [[ buffer(4) ]],
        constant uint& is_horizontal [[ buffer(5) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        uint r = id / n_cols;
        uint c = id % n_cols;
        if (r >= n_rows || c >= n_cols) return;

        int half_win = (int)window_size / 2;
        float window[65]; // Support up to winSize 65
        int count = 0;

        if (is_horizontal) {
            for (int i = -half_win; i <= half_win; i++) {
                int idx = (int)c + i;
                if (idx >= 0 && idx < (int)n_cols) {
                    window[count++] = in[r * n_cols + idx];
                } else {
                    window[count++] = 0.0f;
                }
            }
        } else {
            for (int i = -half_win; i <= half_win; i++) {
                int idx = (int)r + i;
                if (idx >= 0 && idx < (int)n_rows) {
                    window[count++] = in[idx * n_cols + c];
                } else {
                    window[count++] = 0.0f;
                }
            }
        }

        // Bubble sort for small windows in kernel
        for (int i = 0; i < count - 1; i++) {
            for (int j = 0; j < count - i - 1; j++) {
                if (window[j] > window[j+1]) {
                    float temp = window[j];
                    window[j] = window[j+1];
                    window[j+1] = temp;
                }
            }
        }

        out[id] = window[count / 2];
    }
    kernel void calculate_complex_magnitude_phase(
        const device float* real [[ buffer(0) ]],
        const device float* imag [[ buffer(1) ]],
        device float* magnitude [[ buffer(2) ]],
        device float* phase [[ buffer(3) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        float re = real[id];
        float im = imag[id];
        float mag = sqrt(re * re + im * im);
        magnitude[id] = mag;
        
        // Safety: handle atan2(0,0) which can be NaN on some GPUs
        if (mag < 1e-10) {
            phase[id] = 0.0f;
        } else {
            phase[id] = atan2(im, re);
        }
    }

    kernel void window_and_magnitude(
        const device float* samples [[ buffer(0) ]],
        const device float* window [[ buffer(1) ]],
        device float* output [[ buffer(2) ]],
        constant uint& n_fft [[ buffer(3) ]],
        constant uint& hop_length [[ buffer(4) ]],
        uint id [[ thread_position_in_grid ]]
    ) {
        uint frame_idx = id / n_fft;
        uint sample_in_frame = id % n_fft;
        uint total_samples = n_fft * (frame_idx + 1); // Approximation for bounds check
        
        uint sample_idx = frame_idx * hop_length + sample_in_frame;
        
        // Windowing operation
        float s = samples[sample_idx];
        float w = window[sample_in_frame];
        output[id] = s * w;
    }

    """
    
    private var squareState: MTLComputePipelineState?
    private var stressState: MTLComputePipelineState?
    private var dctState: MTLComputePipelineState?
    private var forensicState: MTLComputePipelineState?
    private var medianState: MTLComputePipelineState?
    private var magPhaseState: MTLComputePipelineState?
    private var windowMagState: MTLComputePipelineState?
    
    public init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
        
        if let device = device {
            Swift.print("✅ Metal Engine: GPU Discovery Success — [\(device.name)] Engaged.")
        } else {
            Swift.print("⚠️ Metal Engine: No compatible GPU found. Falling back to Accelerate (AMX/CPU).")
        }
        
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
            if let medianFunc = library.makeFunction(name: "median_filter_2d") {
                self.medianState = try device.makeComputePipelineState(function: medianFunc)
            }
            if let magPhaseFunc = library.makeFunction(name: "calculate_complex_magnitude_phase") {
                self.magPhaseState = try device.makeComputePipelineState(function: magPhaseFunc)
            }
            if let windowMagFunc = library.makeFunction(name: "window_and_magnitude") {
                self.windowMagState = try device.makeComputePipelineState(function: windowMagFunc)
            }
        } catch {
            Swift.print("❌ Metal Engine: Runtime shader compilation failed - \(error.localizedDescription)")
            Swift.print("💡 TIP: Verify M4 specialized kernels are compatible with current macOS version.")
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
            var output = [Float](repeating: 0, count: samples.count)
            vDSP_vsq(samples, 1, &output, 1, vDSP_Length(samples.count))
            return output
        }
        
        let count = samples.count
        let size = count * MemoryLayout<Float>.stride
        
        guard let inBuffer = device.makeBuffer(bytes: samples, length: size, options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            var output = [Float](repeating: 0, count: samples.count)
            vDSP_vsq(samples, 1, &output, 1, vDSP_Length(samples.count))
            return output
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            var output = [Float](repeating: 0, count: samples.count)
            vDSP_vsq(samples, 1, &output, 1, vDSP_Length(samples.count))
            return output
        }
        
        encoder.setComputePipelineState(squareState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = squareState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // --- NEW: Use a semaphore-based wait to allow the OS to register GPU work without spinning the CPU 100% ---
        let semaphore = DispatchSemaphore(value: 0)
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }
        commandBuffer.commit()
        semaphore.wait()
        
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
    
    public func executeMedianFilter2D(
        data: [Float], 
        nRows: Int, 
        nCols: Int, 
        windowSize: Int, 
        isHorizontal: Bool
    ) -> [Float] {
        guard let device = device, let commandQueue = commandQueue, let medianState = medianState, !data.isEmpty else {
            return []
        }
        
        let count = data.count
        let size = count * 4
        
        guard let inBuffer = device.makeBuffer(bytes: data, length: size, options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            return []
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }
        
        encoder.setComputePipelineState(medianState)
        encoder.setBuffer(inBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        
        var uintRows = UInt32(nRows); var uintCols = UInt32(nCols)
        var uintWin = UInt32(windowSize); var uintHor = isHorizontal ? UInt32(1) : UInt32(0)
        
        encoder.setBytes(&uintRows, length: 4, index: 2)
        encoder.setBytes(&uintCols, length: 4, index: 3)
        encoder.setBytes(&uintWin, length: 4, index: 4)
        encoder.setBytes(&uintHor, length: 4, index: 5)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = medianState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let ptr = outBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    public func executeComplexMagnitudePhase(real: [Float], imag: [Float]) -> (magnitude: [Float], phase: [Float]) {
        guard let device = device, let commandQueue = commandQueue, let magPhaseState = magPhaseState, !real.isEmpty else {
            return ([], [])
        }
        
        let count = real.count
        let size = count * 4
        
        guard let rBuf = device.makeBuffer(bytes: real, length: size, options: .storageModeShared),
              let iBuf = device.makeBuffer(bytes: imag, length: size, options: .storageModeShared),
              let mBuf = device.makeBuffer(length: size, options: .storageModeShared),
              let pBuf = device.makeBuffer(length: size, options: .storageModeShared) else {
            return ([], [])
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return ([], [])
        }
        
        encoder.setComputePipelineState(magPhaseState)
        encoder.setBuffer(rBuf, offset: 0, index: 0)
        encoder.setBuffer(iBuf, offset: 0, index: 1)
        encoder.setBuffer(mBuf, offset: 0, index: 2)
        encoder.setBuffer(pBuf, offset: 0, index: 3)
        
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        let w = magPhaseState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // --- SEALED: Telemetry Increment ---
        kernelExecutionCount["complex_magnitude_phase", default: 0] += 1
        
        let mPtr = mBuf.contents().bindMemory(to: Float.self, capacity: count)
        let pPtr = pBuf.contents().bindMemory(to: Float.self, capacity: count)
        
        return (Array(UnsafeBufferPointer(start: mPtr, count: count)),
                Array(UnsafeBufferPointer(start: pPtr, count: count)))
    }

    public func getHardwareStatus() -> String {
        guard let device = device else { return "None (Metal No Supported)" }
        return device.name
    }

    /// v7.6: Optimized Spectral Hook
    public func executeBatchWindowing(samples: [Float], window: [Float], nFFT: Int, hopLength: Int) -> [Float] {
        guard let device = device, let commandQueue = commandQueue, let windowMagState = windowMagState, !samples.isEmpty else {
            return []
        }
        
        let nFrames = 1 + (samples.count - nFFT) / hopLength
        if nFrames <= 0 { return [] }
        
        let sampleSize = samples.count * 4
        let windowSize = window.count * 4
        let outputSize = nFrames * nFFT * 4
        
        guard let sBuf = device.makeBuffer(bytes: samples, length: sampleSize, options: .storageModeShared),
              let wBuf = device.makeBuffer(bytes: window, length: windowSize, options: .storageModeShared),
              let oBuf = device.makeBuffer(length: outputSize, options: .storageModeShared) else {
            return []
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }
        
        // This kernel just windows for now to move data to GPU earlier
        // In a full implementation, we'd use MPSFFT here.
        encoder.setComputePipelineState(windowMagState)
        encoder.setBuffer(sBuf, offset: 0, index: 0)
        encoder.setBuffer(wBuf, offset: 0, index: 1)
        encoder.setBuffer(oBuf, offset: 0, index: 2)
        var uintFFT = UInt32(nFFT); var uintHop = UInt32(hopLength)
        encoder.setBytes(&uintFFT, length: 4, index: 3)
        encoder.setBytes(&uintHop, length: 4, index: 4)
        
        let threadsPerGrid = MTLSize(width: nFrames * nFFT, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: min(nFFT, windowMagState.threadExecutionWidth), height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // --- SEALED: Telemetry Increment ---
        kernelExecutionCount["window_and_magnitude", default: 0] += 1
        
        let oPtr = oBuf.contents().bindMemory(to: Float.self, capacity: nFrames * nFFT)
        return Array(UnsafeBufferPointer(start: oPtr, count: nFrames * nFFT))
    }
}
