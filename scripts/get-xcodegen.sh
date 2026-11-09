#!/bin/bash
# Puts XcodeGen at /tmp/xcodegen/bin/xcodegen (macOS runners).
# 1) The pinned 2.46.0 release zip, checked against its SHA-256. GitHub's download
#    host sometimes answers 504 for minutes, so it is retried for up to ~8 minutes.
# 2) If it still fails: Homebrew's xcodegen (Homebrew checks its own bottle hash).
set -uo pipefail
URL=https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
for i in $(seq 1 32); do
  if curl -fsSL -o /tmp/xcodegen.zip "$URL" && echo "$SHA  /tmp/xcodegen.zip" | shasum -a 256 -c -s; then
    rm -rf /tmp/xcodegen && unzip -q -o /tmp/xcodegen.zip -d /tmp && /tmp/xcodegen/bin/xcodegen --version && exit 0
  fi
  echo "XcodeGen download attempt $i failed; retrying in 15 s"
  sleep 15
done
echo "::warning::XcodeGen release download kept failing; using Homebrew's xcodegen instead"
brew install xcodegen || exit 1
mkdir -p /tmp/xcodegen/bin && ln -sf "$(brew --prefix)/bin/xcodegen" /tmp/xcodegen/bin/xcodegen
/tmp/xcodegen/bin/xcodegen --version
