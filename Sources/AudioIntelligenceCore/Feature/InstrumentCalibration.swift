import Foundation

/// Per-class confidence calibration for `InstrumentEngine` (DEVLOG item 3 / Phase 38 wiring).
///
/// `InstrumentEngine.predict()` decides which labels to INCLUDE using the raw (uncalibrated)
/// score sum against a fixed 0.3 threshold — that decision is intentionally untouched here (see
/// DEVLOG Phase 37: raising it would destroy information a confidence-reading consumer could
/// otherwise recover, for a naive-consumer benefit that doesn't outweigh the cost). What this
/// file changes is what the `confidence` attached to an INCLUDED prediction actually means: the
/// raw score sum is not comparable across classes (Bass@0.31 and Vocals@0.31 meant ~36% and ~74%
/// true precision respectively, measured) — this maps it to a calibrated value that is.
///
/// Fit offline (`Examples/ReliabilityAudit`, `RA_INSTRUMENT_CALIBRATION`) on OpenMIC-2018's
/// official TRAIN partition only (`partitions/split01_train.csv`), validated on the full held-out
/// test partition (`split01_test.csv`, 5,085 clips) — closing evidence: cross-class ECE spread
/// 0.075 -> 0.048 (full-n per class, 374-3171 samples; every class's own ECE dropped
/// individually — e.g. Vocals 0.158->0.061, Piano 0.115->0.013 — not just the spread narrowing by
/// coincidence). A first version of this fit (spread 0.085->0.031, a tighter-looking number) was
/// caught and superseded: it used `AudioLoader.load()`'s converter-internal stereo->mono downmix
/// instead of production's explicit `(L+R)*0.5` (see the feature-path paragraph below) — the
/// numbers above are the corrected, production-loading-path fit; report THESE, not the earlier
/// ones. Method chosen by train sample size, decided before any fitting was run: Platt scaling
/// for the small classes (Bass n=440, Vocals n=407 — robust on limited data where isotonic would
/// overfit), isotonic regression for the larger ones (Piano/Brass/Drums/Strings — flexible enough
/// for shapes a sigmoid would misfit, e.g. Strings/Synth's climb-then-plateau curve).
///
/// Fit-rate, fit-compute-backend, AND fit-loading-path were all verified against production, not
/// assumed: `DNAReportBuilder`'s `analyticalChunk` branch feeds `InstrumentEngine` at the same
/// 22050Hz the fit uses (Phase 35); a direct CPU-vs-GPU comparison on the exact feature chain
/// (STFT/Mel/MFCC/HPSS) found byte-identical raw scores (mean/max |CPU-GPU| = 0.0000 across all 6
/// classes, 2,000 held-out clips), so no GPU-specific refit was needed; and — found only by a
/// same-input identity check between production's real `predict()` output and this offline
/// fit failing at first — the fit now mono-mixes stereo EXACTLY like `analyticalChunk` does
/// (per-channel resample, then explicit `(L+R)*0.5` via vDSP), not via `AudioLoader.load()`'s
/// internal (and numerically different) converter downmix. That fix cut the identity check's max
/// |offline-production| residual ~500x (0.194 -> 0.00038, 138 evaluated pairs) and confined all
/// remaining mismatches to the two Platt classes (Bass/Vocals) -- informative on its own, since
/// Platt is a smooth continuous function that reflects any nonzero raw-score gap proportionally,
/// while isotonic's flat blocks absorb one unless it crosses a block boundary.
///
/// This is NOT a byte-exact match, and will not become one: a second identity-check run
/// (test-clip loading further aligned to production's exact `loadNextChunkStereoManual` call)
/// measured max residual 0.00208 across 55/138 pairs -- smaller per-clip for Bass (~1e-5, down
/// from 0.00038) but newly touching Piano/Keyboard (isotonic) at a few clips. Confirmed, not just
/// plausible: the offline side re-fits its isotonic/Platt models fresh from that run's
/// training-clip scores every run, and this particular re-fit produced a Piano isotonic curve
/// that measurably differs from the one embedded below (e.g. the re-fit evaluated one clip's
/// region at y=0.6010928961748634 and another's at y=0.53125 -- neither value is a block `y` in
/// `models["Piano/Keyboard"]` below), traced to AVFoundation's decode/resample path not being
/// bit-exact run-to-run (a pre-existing, independently-documented noise source in this codebase).
/// **Closure here rests on the measured bound, not on that explanation**: `maxDiff` in the
/// identity check is a running max over every evaluated pair, mismatched or not, so the reported
/// 0.00038 / 0.00208 already covers all 138 / all 55 mismatches respectively, not a printed
/// sample of them. `Estimated`/CLI confidence is exposed to consumers rounded to whole percent
/// (`pct()`, `Int((x*100).rounded())%`), so any residual under 0.005 can never change a displayed
/// value -- both runs clear that bar with >2x margin, which is what wiring is closed against.
///
/// One consequence worth flagging for future readers: because the fit is sensitive to that decode
/// noise, the parameters embedded below are a SNAPSHOT of one fit, not a value a re-fit is
/// guaranteed to reproduce exactly -- re-running `RA_INSTRUMENT_CALIBRATION` later and getting
/// slightly different numbers is expected, not a regression, as long as the resulting residual
/// against these embedded values stays under the 0.005 bound above.
///
/// Strings/Synth is calibrated as honestly as every other class (its ECE improved substantially,
/// same as the rest), but its raw score's underlying separating power (AUC ≈0.57, the lowest of
/// the 6) is unchanged by calibration — a calibrated Strings/Synth confidence will still top out
/// lower than e.g. Vocals/Drums (AUC ≈0.82/0.75). That ceiling is an `InstrumentEngine`
/// profile-quality question (open item 5), not something calibration can or should paper over.
enum InstrumentCalibration {
    struct Platt {
        let A: Double, B: Double
        func apply(_ score: Double) -> Double { 1.0 / (1.0 + exp(A * score + B)) }
    }

    /// Free-form non-decreasing step function (pool-adjacent-violators fit offline). `blocks` is
    /// sorted ascending by `xMin`, with non-decreasing `y` — the same invariant the offline fit
    /// enforces, verified there via a same-input identity check against this exact apply logic
    /// (DEVLOG Phase 38: production `predict()`'s calibrated confidence vs. the offline
    /// pipeline's, same held-out clips, same raw score — must match exactly, since it's the same
    /// deterministic step-function lookup applied to the same input).
    struct Isotonic {
        let blocks: [(xMin: Double, xMax: Double, y: Double)]
        func apply(_ score: Double) -> Double {
            guard let first = blocks.first, let last = blocks.last else { return 0.5 }
            if score <= first.xMin { return first.y }
            if score >= last.xMax { return last.y }
            for b in blocks where score <= b.xMax { return b.y }
            return last.y
        }
    }

    enum Model {
        case platt(Platt), isotonic(Isotonic)
        func apply(_ score: Double) -> Double {
            switch self {
            case .platt(let m): return m.apply(score)
            case .isotonic(let m): return m.apply(score)
            }
        }
    }

    /// Keyed by `InstrumentEngine`'s coarse `Fingerprint.label` — must match those labels
    /// exactly, or a class silently falls through to the uncalibrated-passthrough default in
    /// `calibrate(label:rawScore:)` below.
    static let models: [String: Model] = [
        "Piano/Keyboard": .isotonic(Isotonic(blocks: [ // 22 blocks, train n=2043 (corrected loader)
            (xMin: 0.006481583695858717, xMax: 0.009958481416106224, y: 0.2),
            (xMin: 0.010354701429605484, xMax: 0.015868239104747772, y: 0.23076923076923078),
            (xMin: 0.01668088510632515, xMax: 0.07422113418579102, y: 0.24050632911392406),
            (xMin: 0.07425988465547562, xMax: 0.10791492462158203, y: 0.25806451612903225),
            (xMin: 0.1090550646185875, xMax: 0.2324548065662384, y: 0.3512064343163539),
            (xMin: 0.23302513360977173, xMax: 0.30772534012794495, y: 0.4857142857142857),
            (xMin: 0.3078274428844452, xMax: 0.4243757426738739, y: 0.4953560371517028),
            (xMin: 0.42455387115478516, xMax: 0.4320357143878937, y: 0.5238095238095238),
            (xMin: 0.4320897161960602, xMax: 0.45287343859672546, y: 0.5333333333333333),
            (xMin: 0.4530588984489441, xMax: 0.4755192995071411, y: 0.5909090909090909),
            (xMin: 0.4755897521972656, xMax: 0.6329952478408813, y: 0.6014625228519196),
            (xMin: 0.633741021156311, xMax: 0.6449931859970093, y: 0.6071428571428571),
            (xMin: 0.6462323665618896, xMax: 0.7733852863311768, y: 0.6422018348623854),
            (xMin: 0.7745170593261719, xMax: 0.7756016254425049, y: 0.6666666666666666),
            (xMin: 0.7776353359222412, xMax: 0.7802414894104004, y: 0.6666666666666666),
            (xMin: 0.781157374382019, xMax: 0.7970235347747803, y: 0.6666666666666666),
            (xMin: 0.7983196973800659, xMax: 0.8625808358192444, y: 0.7142857142857143),
            (xMin: 0.8736377358436584, xMax: 0.8736377358436584, y: 1.0),
            (xMin: 0.8778877854347229, xMax: 0.8778877854347229, y: 1.0),
            (xMin: 0.8989259004592896, xMax: 0.8989259004592896, y: 1.0),
            (xMin: 0.8999544382095337, xMax: 0.8999544382095337, y: 1.0),
            (xMin: 0.9029941558837891, xMax: 0.9029941558837891, y: 1.0),
        ])),
        "Bass (Acoustic/Electric)": .platt(Platt(A: -3.661038202388043, B: 2.7103654604135268)), // train n=440
        "Brass/Trumpet": .isotonic(Isotonic(blocks: [ // 36 blocks, train n=1907
            (xMin: 0.03164344280958176, xMax: 0.03164344280958176, y: 0.0),
            (xMin: 0.03773096203804016, xMax: 0.03773096203804016, y: 0.0),
            (xMin: 0.03802485764026642, xMax: 0.03802485764026642, y: 0.0),
            (xMin: 0.039349086582660675, xMax: 0.039349086582660675, y: 0.0),
            (xMin: 0.04070570319890976, xMax: 0.04070570319890976, y: 0.0),
            (xMin: 0.047383539378643036, xMax: 0.047383539378643036, y: 0.0),
            (xMin: 0.04839559644460678, xMax: 0.04839559644460678, y: 0.0),
            (xMin: 0.04855736717581749, xMax: 0.04855736717581749, y: 0.0),
            (xMin: 0.04885265231132507, xMax: 0.04885265231132507, y: 0.0),
            (xMin: 0.04916294664144516, xMax: 0.04916294664144516, y: 0.0),
            (xMin: 0.049436457455158234, xMax: 0.049436457455158234, y: 0.0),
            (xMin: 0.04994433373212814, xMax: 0.04994433373212814, y: 0.0),
            (xMin: 0.05346564203500748, xMax: 0.05346564203500748, y: 0.0),
            (xMin: 0.05434730648994446, xMax: 0.05434730648994446, y: 0.0),
            (xMin: 0.06278422474861145, xMax: 0.06278422474861145, y: 0.0),
            (xMin: 0.06521927565336227, xMax: 0.08452939242124557, y: 0.0625),
            (xMin: 0.08548250794410706, xMax: 0.11720401048660278, y: 0.09523809523809523),
            (xMin: 0.11779764294624329, xMax: 0.12286633253097534, y: 0.14285714285714285),
            (xMin: 0.12380611151456833, xMax: 0.14709438383579254, y: 0.1590909090909091),
            (xMin: 0.14714772999286652, xMax: 0.18101780116558075, y: 0.18604651162790697),
            (xMin: 0.18128696084022522, xMax: 0.21286092698574066, y: 0.18681318681318682),
            (xMin: 0.21292486786842346, xMax: 0.2581416368484497, y: 0.2465753424657534),
            (xMin: 0.2582645118236542, xMax: 0.2656339108943939, y: 0.2857142857142857),
            (xMin: 0.26594218611717224, xMax: 0.3219142258167267, y: 0.32620320855614976),
            (xMin: 0.32236820459365845, xMax: 0.46491938829421997, y: 0.36084452975047987),
            (xMin: 0.46534353494644165, xMax: 0.5347597599029541, y: 0.3918918918918919),
            (xMin: 0.5351117849349976, xMax: 0.5496057271957397, y: 0.3953488372093023),
            (xMin: 0.5502675771713257, xMax: 0.5954399108886719, y: 0.4016393442622951),
            (xMin: 0.5958515405654907, xMax: 0.6710219979286194, y: 0.5085714285714286),
            (xMin: 0.6716655492782593, xMax: 0.7671304941177368, y: 0.5133333333333333),
            (xMin: 0.7681308388710022, xMax: 0.8428899645805359, y: 0.6285714285714286),
            (xMin: 0.8444198966026306, xMax: 0.8444198966026306, y: 1.0),
            (xMin: 0.856947124004364, xMax: 0.856947124004364, y: 1.0),
            (xMin: 0.8570453524589539, xMax: 0.8570453524589539, y: 1.0),
            (xMin: 0.858635663986206, xMax: 0.858635663986206, y: 1.0),
            (xMin: 0.9089243412017822, xMax: 0.9089243412017822, y: 1.0),
        ])),
        "Vocals/Chorus": .platt(Platt(A: -6.502023963125355, B: 2.155936249747514)), // train n=407
        "Drums/Percussion": .isotonic(Isotonic(blocks: [ // 18 blocks, train n=1168
            (xMin: 0.017402874305844307, xMax: 0.05539892986416817, y: 0.2125),
            (xMin: 0.05605241283774376, xMax: 0.18793240189552307, y: 0.27807486631016043),
            (xMin: 0.18795344233512878, xMax: 0.2579420506954193, y: 0.33766233766233766),
            (xMin: 0.2585185766220093, xMax: 0.28423526883125305, y: 0.35135135135135137),
            (xMin: 0.28522878885269165, xMax: 0.34123170375823975, y: 0.359375),
            (xMin: 0.34148484468460083, xMax: 0.35264474153518677, y: 0.4375),
            (xMin: 0.3527222275733948, xMax: 0.41704827547073364, y: 0.45121951219512196),
            (xMin: 0.4172649383544922, xMax: 0.4296247661113739, y: 0.5384615384615384),
            (xMin: 0.4309912621974945, xMax: 0.440546452999115, y: 0.5555555555555556),
            (xMin: 0.4417157769203186, xMax: 0.5042328834533691, y: 0.6619718309859155),
            (xMin: 0.5049384832382202, xMax: 0.5732030272483826, y: 0.6938775510204082),
            (xMin: 0.5735060572624207, xMax: 0.5761401653289795, y: 0.7142857142857143),
            (xMin: 0.5764210224151611, xMax: 0.6824275255203247, y: 0.7647058823529411),
            (xMin: 0.6828771829605103, xMax: 0.7118325233459473, y: 0.8333333333333334),
            (xMin: 0.7118502855300903, xMax: 0.7372483015060425, y: 0.8421052631578947),
            (xMin: 0.7387712597846985, xMax: 0.775027334690094, y: 0.8870967741935484),
            (xMin: 0.7760283946990967, xMax: 0.9088830351829529, y: 0.927007299270073),
            (xMin: 0.9219957590103149, xMax: 0.9219957590103149, y: 1.0),
        ])),
        "Strings/Synth": .isotonic(Isotonic(blocks: [ // 29 blocks, train n=3094
            (xMin: 0.02859618328511715, xMax: 0.02859618328511715, y: 0.0),
            (xMin: 0.031365565955638885, xMax: 0.031365565955638885, y: 0.0),
            (xMin: 0.0337420217692852, xMax: 0.0337420217692852, y: 0.0),
            (xMin: 0.033761538565158844, xMax: 0.033761538565158844, y: 0.0),
            (xMin: 0.03939596936106682, xMax: 0.03939596936106682, y: 0.0),
            (xMin: 0.041153520345687866, xMax: 0.07833104580640793, y: 0.2857142857142857),
            (xMin: 0.07845045626163483, xMax: 0.09547273069620132, y: 0.35294117647058826),
            (xMin: 0.09652186185121536, xMax: 0.14463520050048828, y: 0.3684210526315789),
            (xMin: 0.14467772841453552, xMax: 0.1753154993057251, y: 0.3709677419354839),
            (xMin: 0.17571882903575897, xMax: 0.2892954349517822, y: 0.37888198757763975),
            (xMin: 0.28991812467575073, xMax: 0.30427682399749756, y: 0.4339622641509434),
            (xMin: 0.3042914867401123, xMax: 0.3332470953464508, y: 0.43636363636363634),
            (xMin: 0.33324795961380005, xMax: 0.3918766975402832, y: 0.4642857142857143),
            (xMin: 0.3920944929122925, xMax: 0.5356692671775818, y: 0.5220949263502455),
            (xMin: 0.5356712341308594, xMax: 0.5391152501106262, y: 0.5294117647058824),
            (xMin: 0.5396022796630859, xMax: 0.5770316123962402, y: 0.5304878048780488),
            (xMin: 0.5770617723464966, xMax: 0.6287544369697571, y: 0.5338078291814946),
            (xMin: 0.6288444995880127, xMax: 0.6665871739387512, y: 0.5474137931034483),
            (xMin: 0.6671135425567627, xMax: 0.6680095791816711, y: 0.5555555555555556),
            (xMin: 0.6681146621704102, xMax: 0.7778197526931763, y: 0.5878003696857671),
            (xMin: 0.7780143022537231, xMax: 0.8687801957130432, y: 0.5899280575539568),
            (xMin: 0.8696747422218323, xMax: 0.9118065237998962, y: 0.6666666666666666),
            (xMin: 0.9123359322547913, xMax: 0.9123359322547913, y: 1.0),
            (xMin: 0.9214122295379639, xMax: 0.9214122295379639, y: 1.0),
            (xMin: 0.9309893250465393, xMax: 0.9309893250465393, y: 1.0),
            (xMin: 0.9328389167785645, xMax: 0.9328389167785645, y: 1.0),
            (xMin: 0.93514084815979, xMax: 0.93514084815979, y: 1.0),
            (xMin: 0.9356335401535034, xMax: 0.9356335401535034, y: 1.0),
            (xMin: 0.94141685962677, xMax: 0.94141685962677, y: 1.0),
        ])),
    ]

    /// Maps a coarse label's raw (uncalibrated) score sum to a calibrated confidence in `0...1`.
    /// Falls back to the raw score, clamped, if `label` has no fitted model (should not happen
    /// for any of `InstrumentEngine`'s 6 coarse classes — defensive only).
    static func calibrate(label: String, rawScore: Double) -> Double {
        guard let model = models[label] else { return min(1.0, max(0.0, rawScore)) }
        return model.apply(rawScore)
    }
}
