#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <YouTubePlus.ipa>" >&2
  exit 2
fi

ipa="$1"
script_dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$ipa" ]; then
  echo "IPA not found: $ipa" >&2
  exit 1
fi

ipa_path="$(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa")"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

unzip -q "$ipa_path" -d "$tmp_dir"
app_dir="$(find "$tmp_dir/Payload" -maxdepth 1 -type d -name "*.app" -print -quit)"

if [ -z "$app_dir" ]; then
  echo "Could not find .app bundle in $ipa" >&2
  exit 1
fi

dylib="$app_dir/Frameworks/YTLite.dylib"
if [ ! -f "$dylib" ]; then
  echo "YTLite.dylib not found in injected IPA" >&2
  exit 1
fi

"$script_dir/patch-ytplus-download-id.py" "$dylib"

(
  cd "$tmp_dir"
  rm -f "$ipa_path"
  COPYFILE_DISABLE=1 zip -qr -X "$ipa_path" Payload
)
