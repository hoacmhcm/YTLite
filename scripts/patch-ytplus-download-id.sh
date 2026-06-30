#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <input.deb> [output.deb]" >&2
  exit 2
fi

input_deb="$1"
output_deb="${2:-$1}"

if [ ! -f "$input_deb" ]; then
  echo "Input deb not found: $input_deb" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cp "$input_deb" "$tmp_dir/input.deb"

(
  cd "$tmp_dir"
  ar -x input.deb

  data_archive=""
  for candidate in data.tar.lzma data.tar.xz data.tar.gz data.tar.zst data.tar; do
    if [ -f "$candidate" ]; then
      data_archive="$candidate"
      break
    fi
  done

  if [ -z "$data_archive" ]; then
    echo "Could not find data.tar payload in $input_deb" >&2
    exit 1
  fi

  mkdir data
  case "$data_archive" in
    data.tar.lzma) tar --lzma -xf "$data_archive" -C data ;;
    data.tar.xz) tar -xJf "$data_archive" -C data ;;
    data.tar.gz) tar -xzf "$data_archive" -C data ;;
    data.tar.zst) tar --zstd -xf "$data_archive" -C data ;;
    data.tar) tar -xf "$data_archive" -C data ;;
  esac

  dylib="data/Library/MobileSubstrate/DynamicLibraries/YTLite.dylib"
  if [ ! -f "$dylib" ]; then
    echo "YTLite.dylib not found in $input_deb" >&2
    exit 1
  fi

  "$(dirname "$0")/patch-ytplus-download-id.py" "$dylib"

  rm -f "$data_archive"
  case "$data_archive" in
    data.tar.lzma) COPYFILE_DISABLE=1 tar --lzma -cf "$data_archive" -C data . ;;
    data.tar.xz) COPYFILE_DISABLE=1 tar -cJf "$data_archive" -C data . ;;
    data.tar.gz) COPYFILE_DISABLE=1 tar -czf "$data_archive" -C data . ;;
    data.tar.zst) COPYFILE_DISABLE=1 tar --zstd -cf "$data_archive" -C data . ;;
    data.tar) COPYFILE_DISABLE=1 tar -cf "$data_archive" -C data . ;;
  esac

  python3 - patched.deb debian-binary control.tar.* "$data_archive" <<'PY'
import sys
from pathlib import Path

out = Path(sys.argv[1])
members = [Path(arg) for arg in sys.argv[2:]]

with out.open("wb") as archive:
    archive.write(b"!<arch>\n")

    for member in members:
        name = member.name
        if len(name) > 15:
            raise SystemExit(f"ar member name too long for Debian package: {name}")

        data = member.read_bytes()
        header = (
            f"{name}".ljust(16)
            + f"{0:<12}"
            + f"{0:<6}"
            + f"{0:<6}"
            + f"{0o100644:<8}"
            + f"{len(data):<10}"
            + "`\n"
        ).encode("ascii")

        archive.write(header)
        archive.write(data)
        if len(data) % 2:
            archive.write(b"\n")
PY

  if ! tar -tf patched.deb | grep -Eq '^data\.'; then
    echo "Patched deb validation failed: data archive not found" >&2
    exit 1
  fi
)

cp "$tmp_dir/patched.deb" "$output_deb"
