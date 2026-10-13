#!/usr/bin/env python3
"""Checks an integration run: python3 tools/check_integration.py APP_LOG MOCK_LOG EXPECT_JSON

EXPECT_JSON maps dotted STATS paths to rules, e.g.
  {"client.connects": {"min": 4}, "client_state": {"eq": "READY"}}
Always enforced: a STATS line exists, zero engine/script errors, no
"SCRIPT ERROR", no leaks reported at exit, and the mock finished cleanly.
"""
import json
import re
import sys


def get(stats, path):
    node = stats
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def main():
    app_log, mock_log, expect_path = sys.argv[1:4]
    app = open(app_log, encoding="utf-8", errors="replace").read()
    mock = open(mock_log, encoding="utf-8", errors="replace").read()
    expect = json.load(open(expect_path, encoding="utf-8"))
    problems = []

    m = re.search(r"\[lucidin-chaos\] STATS (\{.*\})", app)
    if not m:
        print("FAIL: no STATS line in app log")
        return 1
    stats = json.loads(m.group(1))

    if "SCRIPT ERROR" in app:
        problems.append("app log contains SCRIPT ERROR")
    for needle in ("leaked at exit", "still in use at exit"):
        if needle in app:
            problems.append(f"app log reports '{needle}'")
    if stats.get("engine_errors") != 0:
        problems.append(f"engine_errors = {stats.get('engine_errors')}")
    if stats.get("script_errors") != 0:
        problems.append(f"script_errors = {stats.get('script_errors')}")
    if "SCRIPT ERROR" in mock:
        problems.append("mock log contains SCRIPT ERROR")
    if "scenario error" in mock or "finished" not in mock:
        problems.append("mock scenario did not finish cleanly")

    for path, rule in expect.items():
        if path.startswith("_"):
            continue
        value = get(stats, path)
        if "eq" in rule and value != rule["eq"]:
            problems.append(f"{path} = {value!r}, expected {rule['eq']!r}")
        if "min" in rule and (not isinstance(value, (int, float)) or value < rule["min"]):
            problems.append(f"{path} = {value!r}, expected >= {rule['min']}")
        if "max" in rule and (not isinstance(value, (int, float)) or value > rule["max"]):
            problems.append(f"{path} = {value!r}, expected <= {rule['max']}")
        if "contains" in rule and (not isinstance(value, (list, dict)) or rule["contains"] not in value):
            problems.append(f"{path} = {value!r}, expected to contain {rule['contains']!r}")

    print("STATS " + json.dumps(stats, indent=2, sort_keys=True))
    if problems:
        for p in problems:
            print("FAIL: " + p)
        return 1
    print("OK: all integration checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
