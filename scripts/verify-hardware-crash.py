#!/usr/bin/env python3
"""Explicit opt-in real gamma crash test. Never part of the ordinary build."""
import json
import pathlib
import subprocess
import sys
import time

binary = str(pathlib.Path(sys.argv[1]).resolve())
def capture():
    result = subprocess.run([binary, "--probe"], capture_output=True, text=True, timeout=10, check=True)
    return json.loads(result.stdout)

before = capture()
crash = subprocess.Popen([binary, "--hardware-crash-smoke"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
stdout, stderr = crash.communicate(timeout=10)
if "CRASH-TEST-ARMED" not in stdout:
    sys.stderr.write(stderr)
    raise SystemExit("Crash test did not arm; no success claimed")
restored = False
for attempt in range(20):
    after = capture()
    if after["tableSHA256"] == before["tableSHA256"]:
        restored = True
        break
    time.sleep(0.1)
print(json.dumps({"parentKilled": crash.returncode == -9, "originalGammaDigestRestored": restored,
                  "displayCount": before["displayCount"], "physicalAppearance": "requires human observation"}, indent=2))
raise SystemExit(0 if restored and crash.returncode == -9 else 1)
