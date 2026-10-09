#!/bin/bash
set -euo pipefail

# build/Gloss.app を作って ~/Applications に入れる。前に入れたものは置き換える
cd "$(dirname "$0")/.."
app="$(./scripts/build-app.sh | tail -n 1)"
destination="$HOME/Applications/Gloss.app"

mkdir -p "$HOME/Applications"
rm -rf "$destination"
ditto "$app" "$destination"
echo "$destination"
