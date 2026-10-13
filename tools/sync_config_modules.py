#!/usr/bin/env python3
"""Rewrites the "modules" section of lucidin_chaos.json from the module
defaults (via tools/dump_default_config.gd), keeping the rest of the file.
Usage: GODOT=godot python3 tools/sync_config_modules.py
Note: this resets module settings to their defaults."""
import json
import os
import re
import subprocess

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
godot = os.environ.get("GODOT", "godot")
out = subprocess.run([godot, "--headless", "--path", root, "--script", "res://tools/dump_default_config.gd"],
                     capture_output=True, text=True).stdout
defaults = json.loads(out[out.index("{"):])
mods = defaults["modules"]
order = [m for m in ("greeter", "critter_race", "bonk") if m in mods] + sorted(m for m in mods if m not in ("greeter", "critter_race", "bonk"))
mods = {k: mods[k] for k in order}
if "bonk" in mods:
    mods["bonk"] = dict(_help="Object types live in 'objects'. Set sprite/sound to a file path (relative to this file) to replace the placeholder shape / add a hit sound.", **mods["bonk"])

body = json.dumps(mods, indent=2)
def collapse(m):
    try:
        return json.dumps(json.loads(m.group(0)))
    except ValueError:
        return m.group(0)
body = re.sub(r'\{\s*"shape"[^{}]*\}', collapse, body)
body = re.sub(r'\[\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\]', r'[\1, \2, \3, \4]', body)
body = re.sub(r'\[\s*("[^"\n]*"(?:,\s*"[^"\n]*")*)\s*\]', lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", body)
body = "\n".join(("  " + l if i > 0 else l) for i, l in enumerate(body.split("\n")))

path = os.path.join(root, "lucidin_chaos.json")
cfg = open(path, encoding="utf-8").read()
start = cfg.index('"modules": ')
end = cfg.index('\n\n  "debug"')
cfg = cfg[:start] + '"modules": ' + body + "," + cfg[end:]
json.loads(cfg)
open(path, "w", encoding="utf-8").write(cfg)
print("updated modules section:", ", ".join(mods))
