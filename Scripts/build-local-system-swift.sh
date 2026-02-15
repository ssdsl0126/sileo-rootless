#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

IOS_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"
PLATFORMS_RAW="${SILEO_PLATFORMS:-iphoneos-arm iphoneos-arm64}"
read -r -a PLATFORMS <<< "$PLATFORMS_RAW"
COMMON_ARGS_BASE=(DEBUG=0 ALL_BOOTSTRAPS=1 "IOS_DEPLOYMENT_TARGET=${IOS_TARGET}" V=0 EMBED_SWIFT_STDLIB=0)

ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1"
    exit 1
  fi
}

validate_system_swift_deb() {
  local deb_file="$1"
  local verify_dir
  verify_dir="$(mktemp -d)"

  dpkg-deb -x "$deb_file" "$verify_dir"

  local app_dir
  app_dir="$(find "$verify_dir" -type d -path '*/Applications/Sileo*.app' | head -n1)"
  if [[ -z "$app_dir" ]]; then
    echo "[FAIL] Unable to locate Sileo.app in $deb_file"
    rm -rf "$verify_dir"
    exit 1
  fi

  local app_exe="$app_dir/Sileo"
  if [[ ! -f "$app_exe" ]]; then
    local cfexe
    cfexe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_dir/Info.plist" 2>/dev/null || echo Sileo)"
    app_exe="$app_dir/$cfexe"
  fi
  if [[ ! -f "$app_exe" ]]; then
    echo "[FAIL] Unable to locate executable in $deb_file"
    rm -rf "$verify_dir"
    exit 1
  fi

  if find "$app_dir/Frameworks" -maxdepth 1 -type f -name 'libswift*.dylib' 2>/dev/null | grep -q .; then
    echo "[FAIL] system-swift package unexpectedly contains embedded libswift*.dylib"
    rm -rf "$verify_dir"
    exit 1
  fi

  if ! xcrun otool -l "$app_exe" | grep -q '/usr/lib/swift'; then
    echo "[FAIL] system-swift package missing /usr/lib/swift rpath"
    rm -rf "$verify_dir"
    exit 1
  fi

  echo "[OK] Validation passed: $(basename "$deb_file")"
  rm -rf "$verify_dir"
}

build_one() {
  local label="$1"
  local platform="$2"
  shift 2

  echo ""
  echo "==> Building ${label} (${platform}, system-swift)"
  make clean
  make package "$@" "SILEO_PLATFORM=${platform}" "${COMMON_ARGS_BASE[@]}"
}

ensure_tool make
ensure_tool dpkg-deb
ensure_tool xcrun

echo "Repo: $ROOT_DIR"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g')"
echo "Platforms: ${PLATFORMS_RAW}, iOS target: ${IOS_TARGET}"

for platform in "${PLATFORMS[@]}"; do
  build_one "Nightly (test)" "$platform" NIGHTLY=1
  build_one "Stable (release)" "$platform" NIGHTLY=0 BETA=0
done

for platform in "${PLATFORMS[@]}"; do
  mapfile -t platform_debs < <(ls -t packages/*_"${platform}"-system-swift.deb 2>/dev/null || true)
  if [[ ${#platform_debs[@]} -lt 2 ]]; then
    echo "[FAIL] Expected at least 2 system-swift packages for ${platform} (nightly + stable)"
    exit 1
  fi
  validate_system_swift_deb "${platform_debs[0]}"
  validate_system_swift_deb "${platform_debs[1]}"
done

echo ""
echo "Done. Generated packages:"
ls -lh packages/*system-swift.deb
