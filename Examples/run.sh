#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$SCRIPT_DIR/.dist"
PACKAGES=(AnimalInterface TrickInterface CatPlugin BackflipPlugin DogPlugin Host)

for package in "${PACKAGES[@]}"; do
    swift build --package-path "$SCRIPT_DIR/$package" -c debug
done

# SwiftPM's macOS debug products carry an @loader_path rpath. Co-locating the
# executable and dylibs makes dyld select this one copy of each shared module.
rm -rf "$DIST"
mkdir -p "$DIST"

bin_path() {
    swift build --package-path "$SCRIPT_DIR/$1" -c debug --show-bin-path
}

cp "$(bin_path Host)/Host" "$DIST/Host"
cp "$(bin_path Host)/libDynasty.dylib" "$DIST/libDynasty.dylib"
cp "$(bin_path AnimalInterface)/libAnimalInterface.dylib" "$DIST/libAnimalInterface.dylib"
cp "$(bin_path TrickInterface)/libTrickInterface.dylib" "$DIST/libTrickInterface.dylib"
cp "$(bin_path CatPlugin)/libCatPlugin.dylib" "$DIST/libCatPlugin.dylib"
cp "$(bin_path BackflipPlugin)/libBackflipPlugin.dylib" "$DIST/libBackflipPlugin.dylib"
cp "$(bin_path DogPlugin)/libDogPlugin.dylib" "$DIST/libDogPlugin.dylib"

export TRICK_PLUGIN_PATH="$DIST/libBackflipPlugin.dylib"
output="$("$DIST/Host" "$DIST")"
echo "$output"
grep -Fq "Cat: Meow" <<<"$output"
grep -Fq "Dog: Woof! (and does a backflip)" <<<"$output"
echo "Expected output verified."
