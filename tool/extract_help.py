"""Regenerates lib/core/help_texts.dart from the Valetudo web interface.

Usage (from the project root, then run `dart format` on the output):
  python3 tool/extract_help.py ../Valetudo/frontend/src lib/core/help_texts.dart
"""
import re, sys, json, os
src = sys.argv[1]
out = sys.argv[2]
files = [
 "components/list_menu/res/Duststreaming.ts", "map/res/MapAnnotationsHelp.ts", "map/res/RobotCoverageMapHelp.ts",
 "map/res/SegmentEditHelp.ts", "map/res/VirtualRestrictionEditHelp.ts", "options/res/MapManagementHelp.ts",
 "options/res/MapUtilitiesHelp.ts", "robot/capabilities/res/DoNotDisturbHelp.ts", "robot/capabilities/res/QuirksHelp.ts",
 "robot/capabilities/res/VoicepackHelp.ts", "robot/res/ConsumablesHelp.ts", "valetudo/res/AboutText.ts",
 "valetudo/res/HelpText.ts", "valetudo/res/UpdaterHelp.ts", "valetudo/timers/res/TimersHelp.ts",
]
def dart_str(s):
    # Raw triple-quoted strings cannot contain ''' -- escape instead.
    s = s.replace('\\', '\\\\').replace("'''", "\\'\\'\\'").replace('$', '\\$')
    return "'''" + s + "'''"
lines = ["// GENERATED from the Valetudo web interface (Apache-2.0, (c) Sören Beye and contributors).",
         "// Source: frontend/src/**/res/*.ts. Do not edit by hand.", "// ignore_for_file: lines_longer_than_80_chars", "", "abstract final class HelpTexts {"]
for f in files:
    text = open(os.path.join(src, f), encoding="utf-8").read()
    for m in re.finditer(r"export const (\w+)\s*=\s*`(.*?)`;", text, re.S):
        name, body = m.group(1), m.group(2)
        if "${" in body:
            continue
        body = body.replace("\\`", "`")
        if name == "AboutText":
            # Valetudo's license section is about Valetudo; the About page
            # shows Valrove's own license instead.
            body = body.split("### License")[0]
        ident = name[0].lower() + name[1:]
        lines.append(f"  static const {ident} = {dart_str(body.strip())};")
        lines.append("")
lines.append("}")
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("wrote", out)
