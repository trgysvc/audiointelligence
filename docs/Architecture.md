# 🏛️ Architecture: The Glass-Box Philosophy

AudioIntelligence is founded on the principle of **Transparent Engineering**. Unlike legacy libraries that hide mathematical complexity behind opaque "Black Box" APIs, we provide a **Glass Box** architecture that exposes signal truth to professional engineers.

---

## 1. Hardware-Centric Design (Apple Silicon)

AudioIntelligence is built from the ground up for the ARM architecture, specifically optimized for **MacBook Pro**, **Studio**, and **iPad Pro** workflows.

### AMX (Apple Matrix Extension)
The majority of our heavy DSP operations (vDSP_DFT, vDSP_conv, Matrix Multiplication) are executed on the AMX. By utilizing the **Accelerate Framework**, we achieve computational throughput that is orders of magnitude faster than standard C++ implementations on ARM.

### ANE (Apple Neural Engine)
Our stem-separation and neural isolation models are explicitly compiled for the ANE. This ensures that while you isolate vocals or instruments, the CPU and GPU remain free for other engineering tasks (e.g., rendering video or processing Plug-ins).

### Unified Memory Architecture (UMA)
We leverage UMA by using "Zero-copy" data structures. Audio samples loaded into RAM are shared between the CPU and GPU without costly bus-transfer penalties, enabling real-time complex spectral rendering.

---

## 2. Modular Engineering Layers

The system is structured into four distinct, isolated tiers to ensure stability and forensic auditability.

### I. The Facade Layer (`AudioIntelligence`)
A thread-safe **Swift Actor** that provides the primary interface for integrations. It manages analysis state, handles the `IntelligenceCache`, and ensures that `async/await` tasks don't block the caller.

### II. The Engine Layer (`AudioIntelligenceCore`)
A collection of 30+ discrete analysis modules. This layer is mathematically isolated, allowing each engine (Loudness, Chroma, NMF) to be unit-tested against industrial synthetic standards in isolation.

### III. The GPGPU Layer (`AudioIntelligenceMetal`)
Custom Metal Shaders written in MSL (Metal Shading Language) for massive parallel signal decomposition tasks that exceed the throughput of the AMX.

### IV. The UI Foundation (`AudioIntelligenceUI`)
A library of engineering-grade visualization components that directly consume the internal DNA models (e.g., `STFTMatrix`, `DNAAnalysis`) for bit-perfect rendering.

---

## 3. Forensic Integrity & Calibration

### The "No-Lie" Policy
Every meter in AudioIntelligence is calibrated against **EBU Tech 3341/3342** test vectors. We do not use "estimated" values; we use the exact mathematical integrals specified by the ITU-R.

### Shannon Entropy Logic
For provenance validation, we implement raw bit-stream scanning. By analyzing the entropy of the Least Significant Bits (LSB), we can mathematically prove if a file is an authentic 24-bit recording or a zero-padded upscale.

---

## 4. Resource Management (Infinity Cache)

To handle professional-scale libraries, we implement a **Hybrid 4GB Cache**.
1. **Memory Trace**: A fast `NSCache` layer for immediate retrieval of recent spectral frames.
2. **Disk Persistence**: A background serialization layer that uses SHA256 content hashes. If a file's content remains unchanged, AudioIntelligence will never re-calculate its spectral features, even if the file is moved or renamed.

---
*For a complete reference of the mathematical engines, see [Engines.md](Engines.md).*
