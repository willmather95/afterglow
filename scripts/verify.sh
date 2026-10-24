#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release --disable-sandbox -Xswiftc -warnings-as-errors
.build/release/AfterglowChecks
python3 scripts/verify-guardian.py .build/release/Afterglow
plutil -lint resources/Info.plist
if rg -n 'YOUR_|TODO|FIXME|sk-proj-[A-Za-z0-9]|AKIA[0-9A-Z]{16}' Sources Tests scripts resources --glob '!*.icns' --glob '!verify.sh'; then
  echo 'FAIL: unresolved marker or credential-shaped literal' >&2
  exit 1
fi
echo 'PASS: release compile, core scenarios, guardian protocol, plist, marker/secret scan'
