#!/usr/bin/env python3
"""Exercise the actual guardian protocol without writing to a display."""
import json
import pathlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1]).resolve()
baseline = [{"displayID": 1, "red": [0, 1], "green": [0, 1], "blue": [0, 1]}]

child = subprocess.Popen([str(binary), "--guardian-fixture"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
child.stdin.write(json.dumps(baseline) + "\n")
child.stdin.flush()
assert child.stdout.readline().strip() == "READY"
assert child.poll() is None, "Guardian must stay alive until parent pipe closes"
child.stdin.close()
assert child.stdout.read().strip() == "RESTORED 1"
assert child.wait(timeout=5) == 0

disarmed = subprocess.run([str(binary), "--guardian-fixture"], input=json.dumps(baseline)+"\nDISARM\n", capture_output=True, text=True, timeout=5)
assert disarmed.returncode == 0
assert "DISARMED" in disarmed.stdout and "RESTORED" not in disarmed.stdout

invalid = subprocess.run([str(binary), "--guardian-fixture"], input="[]\n", capture_output=True, text=True, timeout=5)
assert invalid.returncode == 2
assert "READY" not in invalid.stdout

# A killed surrogate parent must close the pipe and wake its independent helper.
parent_code = '''
import json, subprocess, sys, time
child = subprocess.Popen([sys.argv[1], "--guardian-fixture"], stdin=subprocess.PIPE, stdout=sys.stdout, text=True)
child.stdin.write(json.dumps([{"displayID":1,"red":[0,1],"green":[0,1],"blue":[0,1]}])+"\\n")
child.stdin.flush()
time.sleep(30)
'''
parent = subprocess.Popen([sys.executable, "-c", parent_code, str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
assert parent.stdout.readline().strip() == "READY"
parent.kill()
assert parent.stdout.readline().strip() == "RESTORED 1"
parent.wait(timeout=5)
print(json.dumps({"guardian_protocol": "pass", "invalid_baseline": "pass", "explicit_disarm": "pass", "parent_sigkill_eof": "pass", "display_writes": 0}))
