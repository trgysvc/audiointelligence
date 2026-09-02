import Foundation

// =============================================================================
// Metric Wrappers — the measurement/estimation distinction, encoded in the type
// system.
//
// The whole library is built on one philosophy: a *measurement* is an objective,
// falsifiable, standards-traceable number (loudness, true peak, THD+N). An
// *estimation* is a statistical best-effort interpretation (tempo, key,
// instrument) that is never 100% certain. The report must never blur the two.
//
// `Measured<T>` and `Estimated<T>` make that distinction unavoidable: a measured
// value carries its unit, the standard it conforms to, and whether it was
// validated against a reference implementation; an estimated value carries a
// confidence and the method that produced it. A downstream consumer can branch
// on `.validated` / `.confidence` instead of trusting a fabricated badge.
// =============================================================================

// MARK: - Units & Standards

/// The physical unit a metric is expressed in. Serialized as its display string
/// so JSON/plist consumers get a human-meaningful token (e.g. `"LUFS"`).
public enum MetricUnit: String, Codable, Sendable, CaseIterable {
    case lufs = "LUFS"
    case dBTP = "dBTP"
    case dB = "dB"
    case lu = "LU"
    case percent = "%"
    case hertz = "Hz"
    case bits = "bit"
    case bpm = "BPM"
    case cents = "cents"
    case seconds = "s"
    case count = "count"
    /// A bounded 0…1 ratio / normalized score.
    case ratio = "ratio"
    /// A pure number with no unit (indices, correlations on -1…1, etc.).
    case dimensionless = ""
}

/// The published standard a measurement traces to, when one exists. Spectral
/// descriptors (centroid, MFCC, …) have no formal standard but are validated for
/// numerical parity against `librosa`; those use ``librosaParity``.
public enum MetricStandard: String, Codable, Sendable, CaseIterable {
    case ebuR128       = "EBU R128"
    case ebuTech3342   = "EBU Tech 3342"
    case ituBS1770     = "ITU-R BS.1770"
    case aes17         = "AES17"
    case itu468        = "ITU-R 468"
    case smpte         = "SMPTE RP120"
    /// No formal standard; numerically validated against the librosa reference.
    case librosaParity = "librosa-parity"
}

// MARK: - Measured

/// An objective, deterministic measurement.
///
/// Carries its `unit`, the `standard` it conforms to (if any), and whether the
/// value has been `validated` against a reference implementation. This is the
/// certifiable layer — suitable for engineering/forensic work.
public struct Measured<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value
    public let unit: MetricUnit
    /// The standard this measurement conforms to, or `nil` for descriptive
    /// metrics that have no formal standard.
    public let standard: MetricStandard?
    /// `true` when the implementation has been checked for parity against a
    /// reference tool (`ffmpeg`, `librosa`) or a standard's reference signal.
    public let validated: Bool

    public init(_ value: Value,
                unit: MetricUnit,
                standard: MetricStandard? = nil,
                validated: Bool = false) {
        self.value = value
        self.unit = unit
        self.standard = standard
        self.validated = validated
    }
}

// MARK: - Estimated

/// A statistical estimate — a best-effort interpretation, never a certainty.
///
/// Carries the `confidence` in `0…1` and the `method` that produced it, plus an
/// optional ranked list of `alternatives` (e.g. the relative/parallel key, or a
/// half/double tempo). Consumers decide their own trust threshold instead of
/// being handed a fabricated "verified" badge.
public struct Estimated<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value
    /// Confidence in `0...1`. Default meaning: not a probability guarantee, a relative score
    /// from that metric's own algorithm — comparable within its own outputs (e.g. across tempo
    /// estimates) but not necessarily across different metrics or, for a multi-label metric,
    /// across its own different labels.
    ///
    /// `instruments` is the one exception, and reads differently: each label's confidence is
    /// per-class CALIBRATED (`InstrumentCalibration`, DEVLOG item 3/Phase 38-39, fit on
    /// OpenMIC-2018 train, validated on held-out — cross-class ECE spread 0.075→0.048, wired into
    /// production and verified by a same-input identity check in Phase 39) specifically so it IS
    /// comparable across the 6 instrument classes (a fixed threshold like 0.6 now means
    /// approximately the same true reliability whether the label is Bass or Vocals — it did not
    /// before). A consumer thresholding `instruments` at a fixed confidence will see this as a
    /// behavior change from before Phase 38: the raw score has been replaced by a calibrated one,
    /// so a given cutoff now selects a different, more consistent population of predictions (see
    /// CHANGELOG). Which labels appear at all is untouched (still the raw-score 0.3 inclusion
    /// cutoff, deliberately not recalibrated — see `InstrumentEngine.predict()`), and each label's
    /// RANK relative to other labels on the same clip is untouched too (calibration is monotonic
    /// per class and was never applied to reordering).
    public let confidence: Double
    /// Human-readable description of the algorithm (e.g.
    /// `"Krumhansl-Schmuckler"`, `"autocorrelation + log-normal prior"`).
    public let method: String
    /// Lower-ranked candidates, best-first. `nil` when not applicable.
    public let alternatives: [Alternative<Value>]?

    public init(_ value: Value,
                confidence: Double,
                method: String,
                alternatives: [Alternative<Value>]? = nil) {
        self.value = value
        self.confidence = confidence
        self.method = method
        self.alternatives = alternatives
    }
}

/// A ranked alternative candidate for an ``Estimated`` value.
public struct Alternative<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value
    public let confidence: Double

    public init(_ value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }
}
