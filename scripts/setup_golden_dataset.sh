#!/bin/zsh
# scripts/setup_golden_dataset.sh
# Rebuilds Examples/Golden/ (GiantSteps key+tempo golden set) from public sources.
# This directory is gitignored on purpose (~822 MB) — run this once locally before
# `swift test --filter GoldenDatasetValidationTests`. Mirrors the manual steps that
# used to live only in README.md under "Rebuilding the GiantSteps golden set".

set -e

GOLDEN_DIR="Examples/Golden/giantsteps"
WORK_DIR="/tmp/giantsteps_rebuild"

mkdir -p "$GOLDEN_DIR" "$WORK_DIR"

echo "🚀 Rebuilding GiantSteps golden dataset..."

# 1. Audio (Zenodo, CC-BY — Beatport previews for research)
if [ ! -f "$WORK_DIR/gs.zip" ]; then
    echo "⬇️  Downloading audio.zip (~822 MB) from Zenodo..."
    curl -L "https://zenodo.org/records/1095691/files/audio.zip?download=1" -o "$WORK_DIR/gs.zip"
fi
if [ ! -d "$WORK_DIR/audio" ]; then
    echo "📦 Extracting audio..."
    unzip -q "$WORK_DIR/gs.zip" -d "$WORK_DIR/audio"
fi

# 2. Annotations (GitHub — MIREX key/tempo ground truth)
if [ ! -d "$WORK_DIR/gs-key" ]; then
    echo "⬇️  Cloning key annotations..."
    git clone --depth 1 https://github.com/GiantSteps/giantsteps-key-dataset.git "$WORK_DIR/gs-key"
fi
if [ ! -d "$WORK_DIR/gs-tempo" ]; then
    echo "⬇️  Cloning tempo annotations..."
    git clone --depth 1 https://github.com/GiantSteps/giantsteps-tempo-dataset.git "$WORK_DIR/gs-tempo"
fi

# 3. Match audio <-> annotations, copy mp3s into place, emit manifest.json
#    matching Tests/GoldenDatasetValidationTests.swift's expected schema:
#      { "files": [ { "id": String, "file": String, "key": String, "bpm": Int? } ] }
#    NOTE: this step has NOT been run/verified against the live datasets in this repo
#    (would require the ~822 MB download to test). If the key/tempo annotation file
#    layout in the cloned repos differs from what's assumed below, adjust the `find`
#    patterns accordingly — the audio<->annotation ID matching is the part most likely
#    to need a tweak on first real run.
python3 - "$WORK_DIR" "$GOLDEN_DIR" <<'PYEOF'
import sys, os, json, glob, shutil

work_dir, golden_dir = sys.argv[1], sys.argv[2]
audio_dir = os.path.join(work_dir, "audio")
key_dir   = os.path.join(work_dir, "gs-key", "annotations", "key")
tempo_dir = os.path.join(work_dir, "gs-tempo", "annotations", "tempo")

entries = []
for audio_path in sorted(glob.glob(os.path.join(audio_dir, "**", "*.mp3"), recursive=True)):
    track_id = os.path.splitext(os.path.basename(audio_path))[0]
    key_file = os.path.join(key_dir, f"{track_id}.key")
    if not os.path.isfile(key_file):
        continue  # only tracks with a real key annotation go in the golden set
    with open(key_file) as f:
        key = f.read().strip()

    bpm = None
    tempo_file = os.path.join(tempo_dir, f"{track_id}.bpm")
    if os.path.isfile(tempo_file):
        with open(tempo_file) as f:
            try:
                bpm = round(float(f.read().strip()))
            except ValueError:
                pass

    dest = os.path.join(golden_dir, f"{track_id}.mp3")
    shutil.copyfile(audio_path, dest)
    entries.append({"id": track_id, "file": f"{track_id}.mp3", "key": key, "bpm": bpm})

manifest_path = os.path.join(os.path.dirname(golden_dir), "manifest.json")
with open(manifest_path, "w") as f:
    json.dump({"files": entries}, f, indent=2)

print(f"✅ {len(entries)} tracks written to {golden_dir}, manifest at {manifest_path}")
PYEOF

echo "Done. Run: swift test --filter GoldenDatasetValidationTests"
