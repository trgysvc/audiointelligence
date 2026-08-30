#!/usr/bin/env python3
"""
Reference cross-check for AudioIntelligence's STFT/mel foundational DSP claim.

Reads the raw float32 dumps written by `swift test --filter ParityDumpTests`
(the identical deterministic multi-tone signal AND our engine's STFT-magnitude
and mel-spectrogram output), computes librosa's STFT/mel on the SAME samples
with matched conventions, and reports Pearson correlation + relative residual.

Run: swift test --filter ParityDumpTests   (writes /tmp/parity/*.f32)
     /tmp/lrvenv/bin/python scripts/parity_compare.py

Verified 2026-08-30 (this exact script, this exact repo state): STFT corr=1.00000/residual=0.0000%,
Mel corr=1.00000/residual=0.0003% — confirms README's "librosa-exact" claim. See DEVLOG.
"""
import numpy as np
import librosa
import scipy.fftpack
import sys

DIR = "/tmp/parity"
SR = 22050


def read_f32(path):
    return np.fromfile(path, dtype=np.float32)


def load_signal():
    return read_f32(f"{DIR}/signal.f32")


def load_swift_stft():
    raw = read_f32(f"{DIR}/swift_stft.f32")
    n_frames, n_freqs = int(raw[0]), int(raw[1])
    data = raw[2:]
    expected = n_frames * n_freqs
    if data.size != expected:
        print(f"❌ swift_stft.f32 size mismatch: got {data.size}, expected {expected}")
        sys.exit(1)
    # Swift layout: magnitude[t * nFreqs + f]  ->  frame-major (nFrames, nFreqs)
    return data.reshape(n_frames, n_freqs)


def load_swift_mel():
    raw = read_f32(f"{DIR}/swift_mel.f32")
    n_mels, n_frames = int(raw[0]), int(raw[1])  # header order
    data = raw[2:]
    expected = n_mels * n_frames
    if data.size != expected:
        print(f"❌ swift_mel.f32 size mismatch: got {data.size}, expected {expected}")
        sys.exit(1)
    # NOTE: header is [nMels, nFrames] but the underlying MelSpectrogramResult.melData is
    # actually frame-major (melData[t * nMels + m], per MelSpectrogramEngine.swift) — the
    # header order does NOT match the data layout. Reshape as (nFrames, nMels), not (nMels, nFrames).
    return data.reshape(n_frames, n_mels)


def load_swift_mfcc():
    raw = read_f32(f"{DIR}/swift_mfcc.f32")
    n_mfcc, n_frames = int(raw[0]), int(raw[1])  # header order
    data = raw[2:]
    expected = n_mfcc * n_frames
    if data.size != expected:
        print(f"❌ swift_mfcc.f32 size mismatch: got {data.size}, expected {expected}")
        sys.exit(1)
    # Dumped via MetalEngine().executeBatchDct — the GPU batch_dct kernel indexes
    # out[frame_idx * n_mfcc + mfcc_idx] (AudioIntelligenceMetal.swift), i.e. frame-major,
    # same header/layout mismatch pattern as swift_mel.f32. Reshape as (nFrames, nMfcc).
    return data.reshape(n_frames, n_mfcc)


def pearson(a, b):
    a = a.flatten().astype(np.float64)
    b = b.flatten().astype(np.float64)
    if a.size != b.size:
        print(f"❌ shape mismatch for correlation: {a.size} vs {b.size}")
        return float("nan")
    return float(np.corrcoef(a, b)[0, 1])


def relative_residual(a, b):
    a = a.flatten().astype(np.float64)
    b = b.flatten().astype(np.float64)
    num = np.linalg.norm(a - b)
    den = np.linalg.norm(a)
    return float(num / den) if den > 0 else float("nan")


def main():
    y = load_signal()
    print(f"signal: {y.size} samples ({y.size / SR:.2f}s @ {SR}Hz)")

    # --- STFT magnitude ---
    # Swift convention (ParityDumpTests doc comment): nFFT=2048, hop=512, Hann, center=True,
    # constant pad.
    S = librosa.stft(y, n_fft=2048, hop_length=512, window="hann",
                      center=True, pad_mode="constant")
    librosa_mag = np.abs(S).T  # librosa: (n_freqs, n_frames) -> transpose to (n_frames, n_freqs)

    swift_mag = load_swift_stft()
    print(f"\n=== STFT magnitude ===")
    print(f"librosa shape: {librosa_mag.shape}   swift shape: {swift_mag.shape}")
    if librosa_mag.shape != swift_mag.shape:
        print("❌ SHAPE MISMATCH — cannot compare directly, dumping first-N-frame overlap only")
        n = min(librosa_mag.shape[0], swift_mag.shape[0])
        librosa_mag = librosa_mag[:n]
        swift_mag = swift_mag[:n]
    corr = pearson(swift_mag, librosa_mag)
    resid = relative_residual(swift_mag, librosa_mag)
    print(f"Pearson correlation: {corr:.5f}")
    print(f"Relative residual (||swift-librosa||/||librosa||): {resid*100:.4f}%")

    # --- Mel spectrogram (power) ---
    # Swift: power spectrogram (magnitude^2) through a Slaney-normalized, htk=False mel
    # filterbank (fmin=0, fmax=sr/2) — matches librosa's defaults for melspectrogram/filters.mel.
    mel_power = librosa.feature.melspectrogram(y=y, sr=SR, n_fft=2048, hop_length=512,
                                                n_mels=128, power=2.0,
                                                fmin=0.0, fmax=SR / 2.0,
                                                htk=False, norm="slaney")
    librosa_mel = mel_power.T  # (n_mels, n_frames) -> (n_frames, n_mels)

    swift_mel = load_swift_mel()
    print(f"\n=== Mel spectrogram (power) ===")
    print(f"librosa shape: {librosa_mel.shape}   swift shape: {swift_mel.shape}")
    if librosa_mel.shape != swift_mel.shape:
        print("❌ SHAPE MISMATCH — cannot compare directly, dumping first-N-frame overlap only")
        n = min(librosa_mel.shape[0], swift_mel.shape[0])
        librosa_mel = librosa_mel[:n]
        swift_mel = swift_mel[:n]
    corr_mel = pearson(swift_mel, librosa_mel)
    resid_mel = relative_residual(swift_mel, librosa_mel)
    print(f"Pearson correlation: {corr_mel:.5f}")
    print(f"Relative residual (||swift-librosa||/||librosa||): {resid_mel*100:.4f}%")

    # --- MFCC (GPU batch_dct path) ---
    # Swift (MetalEngine.executeBatchDct, post-fix): logMel = 10*log10(max(mel, 1e-10))  [NO
    # top_db clipping], then DCT-II with dcScale=sqrt(1/N) for coeff 0, orthoScale=sqrt(2/N)
    # for the rest — i.e. scipy's dct(type=2, norm='ortho') convention. Reference is built the
    # same way here (not via librosa.feature.mfcc, which assumes power_to_db's default
    # top_db=80 clipping that Swift's simpler log step does not do) so the two are apples-to-apples.
    log_mel_ref = 10.0 * np.log10(np.maximum(mel_power, 1e-10))  # (n_mels, n_frames), unclipped
    mfcc_ref = scipy.fftpack.dct(log_mel_ref, type=2, norm="ortho", axis=0)[:20]  # (20, n_frames)
    librosa_mfcc = mfcc_ref.T  # -> (n_frames, 20)

    swift_mfcc = load_swift_mfcc()
    print(f"\n=== MFCC (GPU batch_dct, post Phase-19-fix) ===")
    print(f"reference shape: {librosa_mfcc.shape}   swift shape: {swift_mfcc.shape}")
    if librosa_mfcc.shape != swift_mfcc.shape:
        print("❌ SHAPE MISMATCH — cannot compare directly, dumping first-N-frame overlap only")
        n = min(librosa_mfcc.shape[0], swift_mfcc.shape[0])
        librosa_mfcc = librosa_mfcc[:n]
        swift_mfcc = swift_mfcc[:n]
    corr_mfcc = pearson(swift_mfcc, librosa_mfcc)
    resid_mfcc = relative_residual(swift_mfcc, librosa_mfcc)
    print(f"Pearson correlation: {corr_mfcc:.5f}")
    print(f"Relative residual (||swift-ref||/||ref||): {resid_mfcc*100:.4f}%")
    # DC term (coeff 0) isolated — this is the exact coefficient the Phase 19 GPU shader bug
    # (unconditional sqrt(2/N) instead of sqrt(1/N) for coeff 0) distorted by a factor of sqrt(2).
    dc_resid = relative_residual(swift_mfcc[:, 0], librosa_mfcc[:, 0])
    print(f"DC term (coeff 0) relative residual: {dc_resid*100:.4f}%  (this is what Phase 19 fixed)")

    print("\n=== Summary ===")
    print(f"STFT  : corr={corr:.5f}  residual={resid*100:.4f}%")
    print(f"Mel   : corr={corr_mel:.5f}  residual={resid_mel*100:.4f}%")
    print(f"MFCC  : corr={corr_mfcc:.5f}  residual={resid_mfcc*100:.4f}%  (DC-term residual={dc_resid*100:.4f}%)")


if __name__ == "__main__":
    main()
