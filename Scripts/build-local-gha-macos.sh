#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Assume required tools/dependencies are already installed on local macOS.
export PATH="/opt/procursus/sbin:/opt/procursus/bin:$PATH"

echo "Resolving Swift packages"
make clean
xcodebuild -resolvePackageDependencies -project Sileo.xcodeproj -scheme Sileo -derivedDataPath "${TMPDIR}/sileo"

alderis_file="${TMPDIR}/sileo/SourcePackages/checkouts/Alderis/Alderis/ColorPickerInnerViewController.swift"
if [[ ! -f "$alderis_file" ]]; then
  echo "ERROR: Alderis source file not found: $alderis_file"
  exit 1
fi

if ! grep -q 'var pickerTab: ColorPickerTab' "$alderis_file"; then
  sed -i '' 's/var tab: ColorPickerTab/var pickerTab: ColorPickerTab/' "$alderis_file"
  sed -i '' 's/tab = configuration.initialTab/pickerTab = configuration.initialTab/' "$alderis_file"
fi

echo "Building nightly package (iphoneos-arm64)"
make package NIGHTLY=1 DEBUG=0 ALL_BOOTSTRAPS=1 SILEO_PLATFORM=iphoneos-arm64 IOS_DEPLOYMENT_TARGET=13.0 V=1

echo ""
echo "Done. Generated artifacts:"
ls -lh packages/* || true
