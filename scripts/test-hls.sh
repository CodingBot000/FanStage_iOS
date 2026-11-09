#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
android_dir="${FANSTAGE_ANDROID_DIR:-$repo_dir/../FanStage}"
cd "$repo_dir"
if lsof -iTCP:28766 -sTCP:LISTEN -t >/dev/null; then echo 'Test port unavailable'; exit 1; fi
python3 -m http.server 28766 --bind 127.0.0.1 --directory $android_dir/android/app/src/androidTest/assets/player001 > /tmp/fanstage-hls-server.log 2>&1 &
server_pid=$!
cleanup() { xcrun simctl spawn booted launchctl unsetenv FANSTAGE_TEST_HLS || true; kill "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT
xcrun simctl spawn booted launchctl setenv FANSTAGE_TEST_HLS http://127.0.0.1:28766/master.m3u8
xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for devices in d["devices"].values() for x in devices if x["state"] == "Booted"))')" -derivedDataPath /tmp/FanStageiOSDerived CODE_SIGNING_ALLOWED=NO test > /tmp/fanstage-hls-test.log 2>&1
rg 'testHLSWhenConfigured|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)' /tmp/fanstage-hls-test.log | tail -10
