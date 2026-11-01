from pathlib import Path
import re

project = Path("project.godot")
if not project.is_file():
    raise SystemExit("ERROR: run this from the SpotRush project root (project.godot not found).")
text = project.read_text(encoding="utf-8")
match = re.search(r"(?ms)^\[autoload\]\s*\n(.*?)(?=^\[|\Z)", text)
if not match:
    raise SystemExit("ERROR: [autoload] section not found in project.godot.")
block = match.group(1)
fixed = re.sub(r"(?m)^(\s*)#(\s*EOSG 2\.3\.1 runtime services.*|\s*exports do not depend.*)$", r"\1;\2", block)
if fixed == block:
    print("No EOSG hash-comment lines found in [autoload]; no changes made.")
else:
    text = text[:match.start(1)] + fixed + text[match.end(1):]
    project.write_text(text, encoding="utf-8", newline="")
    print("Fixed EOSG comments in [autoload]. Remove any existing '# EOSG...' ghost autoload row if it remains in Project Settings.")
