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

  python3 - "$dylib" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
binary = bytearray(path.read_bytes())

old = b"id.ui.add_to.offline.button"
new = b"id.video.add_to.button"

if len(new) > len(old):
    raise SystemExit("Replacement identifier is longer than the original")

old_offset = binary.find(old)
if old_offset < 0:
    print("Download identifier patch skipped: old identifier not found")
    raise SystemExit(0)

if binary.find(new) < 0:
    print("Warning: replacement identifier is not present elsewhere in the binary")

binary[old_offset:old_offset + len(old)] = new + (b"\0" * (len(old) - len(new)))

patched_lengths = 0
old_length = len(old)
new_length = len(new)

for index in range(0, len(binary) - 16, 8):
    value = struct.unpack_from("<Q", binary, index)[0]
    if (value & 0xFFFFFFFF) != old_offset:
        continue

    length_offset = index + 8
    length = struct.unpack_from("<Q", binary, length_offset)[0]
    if length == old_length:
        struct.pack_into("<Q", binary, length_offset, new_length)
        patched_lengths += 1

if patched_lengths == 0:
    raise SystemExit("Could not patch CFString length for download identifier")

path.write_bytes(binary)
print(f"Patched download identifier: {old.decode()} -> {new.decode()} ({patched_lengths} CFString length field)")
PY

  rm -f "$data_archive"
  case "$data_archive" in
    data.tar.lzma) COPYFILE_DISABLE=1 tar --lzma -cf "$data_archive" -C data . ;;
    data.tar.xz) COPYFILE_DISABLE=1 tar -cJf "$data_archive" -C data . ;;
    data.tar.gz) COPYFILE_DISABLE=1 tar -czf "$data_archive" -C data . ;;
    data.tar.zst) COPYFILE_DISABLE=1 tar --zstd -cf "$data_archive" -C data . ;;
    data.tar) COPYFILE_DISABLE=1 tar -cf "$data_archive" -C data . ;;
  esac

  ar -cr patched.deb debian-binary control.tar.* "$data_archive"
)

cp "$tmp_dir/patched.deb" "$output_deb"
