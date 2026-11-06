#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project/Resources/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
archive="$project/dist/Ada-$version-AppleSilicon.dmg"
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
mkdir -p "$project/dist/Casks"
cat > "$project/dist/Casks/ada-island.rb" <<CASK
cask "ada-island" do
  version "$version"
  sha256 "$checksum"

  url "https://github.com/frozenruzgar/ada-dynamic-island/releases/download/v#{version}/Ada-#{version}-AppleSilicon.dmg"
  name "Ada"
  desc "MacBook notch workspace with media, files, and focus tools"
  homepage "https://github.com/frozenruzgar/ada-dynamic-island"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Ada.app"
end
CASK
ruby -c "$project/dist/Casks/ada-island.rb"
