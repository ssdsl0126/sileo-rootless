#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="/opt/procursus/sbin:/opt/procursus/bin:$PATH"

IOS_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/sileo}"
PLATFORMS_RAW="${SILEO_PLATFORMS:-iphoneos-arm iphoneos-arm64}"
read -r -a PLATFORMS <<< "$PLATFORMS_RAW"

ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1"
    exit 1
  fi
}

patch_alderis_if_needed() {
  local alderis_file="$1"
  if [[ ! -f "$alderis_file" ]]; then
    echo "ERROR: Alderis source file not found: $alderis_file"
    exit 1
  fi

  if ! grep -q 'var pickerTab: ColorPickerTab' "$alderis_file"; then
    sed -i '' 's/var tab: ColorPickerTab/var pickerTab: ColorPickerTab/' "$alderis_file"
    sed -i '' 's/tab = configuration.initialTab/pickerTab = configuration.initialTab/' "$alderis_file"
  fi
}

resolve_swift_packages() {
  echo "Resolving Swift packages"
  xcodebuild -resolvePackageDependencies \
    -project Sileo.xcodeproj \
    -scheme Sileo \
    -derivedDataPath "$DERIVED_DATA_PATH"

  patch_alderis_if_needed "$DERIVED_DATA_PATH/SourcePackages/checkouts/Alderis/Alderis/ColorPickerInnerViewController.swift"
}

build_one() {
  local platform="$1"

  echo ""
  echo "Building release package (${platform})"
  make clean
  resolve_swift_packages
  make package \
    DEBUG=0 \
    BETA=0 \
    NIGHTLY=0 \
    ALL_BOOTSTRAPS=1 \
    SILEO_PLATFORM="${platform}" \
    IOS_DEPLOYMENT_TARGET="${IOS_TARGET}" \
    V=1
}

ensure_tool make
ensure_tool xcodebuild

echo "Repo: $ROOT_DIR"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g')"
echo "Platforms: ${PLATFORMS_RAW}"
echo "iOS target: ${IOS_TARGET}"
echo "Derived data: ${DERIVED_DATA_PATH}"

for platform in "${PLATFORMS[@]}"; do
  build_one "$platform"
done

echo ""
echo "Done. Generated release artifacts:"
ls -lh packages/*_iphoneos-arm.deb packages/*_iphoneos-arm64.deb 2>/dev/null || ls -lh packages/* || true
