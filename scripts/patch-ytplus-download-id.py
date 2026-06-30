#!/usr/bin/env python3
import struct
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <YTLite.dylib>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"YTLite.dylib not found: {path}", file=sys.stderr)
        return 1

    binary = bytearray(path.read_bytes())

    old = b"id.ui.add_to.offline.button"
    new = b"id.video.add_to.button"

    if len(new) > len(old):
        print("Replacement identifier is longer than the original", file=sys.stderr)
        return 1

    old_offset = binary.find(old)
    if old_offset < 0:
        print("Download identifier patch skipped: old identifier not found")
        return 0

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
        print("Could not patch CFString length for download identifier", file=sys.stderr)
        return 1

    path.write_bytes(binary)
    print(
        f"Patched download identifier: {old.decode()} -> "
        f"{new.decode()} ({patched_lengths} CFString length field)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
