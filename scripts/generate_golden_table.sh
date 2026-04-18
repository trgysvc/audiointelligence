#!/bin/bash
# scripts/generate_golden_table.sh
# AudioIntelligence v6.3: Automated Laboratory Cross-Validation Script.

set -e

# Configuration
FIXTURE_DIR="Tests/Resources/SQAM"
OUTPUT_FILE="Tests/Resources/sqam_reference_values.txt"

# Search for ffmpeg (check brew paths for macos-15 compatibility)
FFMPEG_PATH=$(which ffmpeg || echo "/opt/homebrew/bin/ffmpeg")

if [ ! -f "$FFMPEG_PATH" ]; then
    echo "❌ Error: ffmpeg not found. Please install via 'brew install ffmpeg'."
    exit 1
fi

echo "🧪 AudioIntelligence: Generating Scientific Golden References..."
echo "# SQAM Scientific Reference Table (EBU R128 via ffmpeg/ebur128)" > "$OUTPUT_FILE"
echo "# Generated: $(date)" >> "$OUTPUT_FILE"
echo "# Format: Filename | Integrated (LUFS) | True Peak (dBTP) | LRA (LU)" >> "$OUTPUT_FILE"

# Check if directory exists
if [ ! -d "$FIXTURE_DIR" ]; then
    echo "⚠️ Warning: $FIXTURE_DIR not found. Skipping generation."
    exit 0
fi

# Iterate through SQAM WAV files
for f in "$FIXTURE_DIR"/*.wav; do
    [ -e "$f" ] || continue
    NAME=$(basename "$f")
    
    echo "Processing $NAME..."
    
    # Run ffmpeg ebur128 analysis
    # peak=true enables true peak detection
    STATS=$("$FFMPEG_PATH" -i "$f" -filter_complex ebur128=peak=true -f null - 2>&1)
    
    # Precise extraction using grep/awk
    I=$(echo "$STATS" | grep "Integrated loudness:" -A 1 | grep "I:" | awk '{print $2}')
    TPK=$(echo "$STATS" | grep "True peak:" -A 1 | grep "Peak:" | awk '{print $2}')
    LRA=$(echo "$STATS" | grep "Loudness range:" -A 1 | grep "LRA:" | awk '{print $2}')
    
    # Format and save
    printf "%-30s | %8s | %8s | %8s\n" "$NAME" "$I" "$TPK" "$LRA" >> "$OUTPUT_FILE"
done

echo "✅ Success: Golden Table generated at $OUTPUT_FILE"
cat "$OUTPUT_FILE"
