#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Assume required tools/dependencies are already installed on local macOS.
export PATH="/opt/procursus/sbin:/opt/procursus/bin:$PATH"

echo "Resolving Swift packages"
make clean
xcodebuild -resolvePackageDependencies -project Sileo.xcodeproj -scheme Sileo -derivedDataPath "${TMPDIR}/sileo"

echo "Building nightly package (iphoneos-arm64)"
make package NIGHTLY=1 DEBUG=0 ALL_BOOTSTRAPS=1 SILEO_PLATFORM=iphoneos-arm64 IOS_DEPLOYMENT_TARGET=15.0 V=1

echo ""
echo "Done. Generated artifacts:"
ls -lh packages/* || true
