#!/bin/zsh
# scripts/setup_test_fixtures.sh
# Professional fixture setup for AudioIntelligence Scientific Validation.

set -e

FIXTURE_DIR="Tests/Resources/SQAM"
mkdir -p "$FIXTURE_DIR"

# SQAM tracks mapping (Track Index | Name)
# Format: index,name
TRACKS_LIST=(
    "21,trpt21_2.wav"
    "23,horn23_2.wav"
    "40,harp40_1.wav"
    "49,spfe49_1.wav"
    "35,gspi35_1.wav"
    "48,quar48_1.wav"
)

BASE_URL="http://sound.media.mit.edu/resources/sqam"

echo "🚀 Downloading Scientific SQAM Fixtures (ZSH Mode)..."

for entry in "${TRACKS_LIST[@]}"; do
    IFS=',' read -r idx file <<< "$entry"
    TARGET="$FIXTURE_DIR/$file"
    
    if [ ! -f "$TARGET" ]; then
        echo "⬇️ Processing $file (Track $idx)..."
        LOCAL_SOURCE="/Users/trgysvc/Downloads/SQAM_FLAC_00s9l4/$(printf "%02d" $idx).flac"
        
        if [ -f "$LOCAL_SOURCE" ]; then
            echo "📦 Converting local $LOCAL_SOURCE to $TARGET..."
            /opt/homebrew/bin/ffmpeg -i "$LOCAL_SOURCE" -ar 44100 -ac 1 "$TARGET" -y -loglevel error
        else
            echo "🌐 Fetching from remote $BASE_URL/$file..."
            curl -s -L "$BASE_URL/$file" -o "$TARGET"
        fi
    else
        echo "✅ $file already exists."
    fi
done

echo "✨ Fixtures ready in $FIXTURE_DIR"
