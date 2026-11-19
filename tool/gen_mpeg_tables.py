"""Regenerates lib/features/camera/mpeg/mpeg1_tables.dart from jsmpeg.

Usage (from the project root, then run `dart format` on the output):
  python3 tool/gen_mpeg_tables.py <jsmpeg>/src/mpeg1.js lib/features/camera/mpeg/mpeg1_tables.dart

jsmpeg: https://github.com/phoboslab/jsmpeg (MIT License).
"""
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
out_path = sys.argv[2]
types = {"Uint8Array": "Uint8List", "Int8Array": "Int8List", "Int16Array": "Int16List", "Int32Array": "Int32List"}
names = ["ZIG_ZAG", "DEFAULT_INTRA_QUANT_MATRIX", "DEFAULT_NON_INTRA_QUANT_MATRIX", "PREMULTIPLIER_MATRIX",
         "MACROBLOCK_ADDRESS_INCREMENT", "MACROBLOCK_TYPE_INTRA", "MACROBLOCK_TYPE_PREDICTIVE", "MACROBLOCK_TYPE_B",
         "CODE_BLOCK_PATTERN", "MOTION", "DCT_DC_SIZE_LUMINANCE", "DCT_DC_SIZE_CHROMINANCE", "DCT_COEFF"]
def camel(n):
    parts = n.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])
lines = [
  "// GENERATED from jsmpeg's mpeg1.js (MIT License, (c) 2017 Dominic Szablewski).",
  "// VLC tables and constants of the MPEG-1 video decoder. Do not edit by hand.",
  "// ignore_for_file: lines_longer_than_80_chars",
  "",
  "import 'dart:typed_data';",
  "",
]
for n in names:
    m = re.search(r"MPEG1\." + n + r" = new (\w+)\(\[(.*?)\]\);", src, re.S)
    if not m:
        sys.exit("missing " + n)
    t, body = types[m.group(1)], m.group(2)
    lines.append(f"final {camel(n)} = {t}.fromList(const [{body.rstrip()}\n]);")
    lines.append("")
open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("ok", out_path)
