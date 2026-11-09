#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
android_dir="${FANSTAGE_ANDROID_DIR:-$repo_dir/../FanStage}"
cd "$repo_dir"
export FANSTAGE_DB_USER=ios_integration
export FANSTAGE_DB_PASSWORD="$(openssl rand -hex 24)"
export FANSTAGE_TOKEN_ALICE="$(openssl rand -hex 32)"
export FANSTAGE_TOKEN_BOB="$(openssl rand -hex 32)"
export FANSTAGE_PORT=28765
project=fanstage-ios-validation-$(openssl rand -hex 4)
cleanup() {
 xcrun simctl spawn booted launchctl unsetenv FANSTAGE_TEST_URL || true
 xcrun simctl spawn booted launchctl unsetenv FANSTAGE_TEST_TOKEN || true
 docker compose -p "$project" -f $android_dir/compose.yaml down >/dev/null 2>&1 || true
}
trap cleanup EXIT
if lsof -iTCP:28765 -sTCP:LISTEN -t >/dev/null; then echo 'Test port unavailable'; exit 1; fi
docker compose -p "$project" -f $android_dir/compose.yaml up --build -d >/tmp/fanstage-ios-compose.log 2>&1
for i in {1..60}; do if curl -fsS http://127.0.0.1:28765/health >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS http://127.0.0.1:28765/health >/dev/null
xcrun simctl spawn booted launchctl setenv FANSTAGE_TEST_URL http://127.0.0.1:28765
xcrun simctl spawn booted launchctl setenv FANSTAGE_TEST_TOKEN "$FANSTAGE_TOKEN_ALICE"
xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for devices in d["devices"].values() for x in devices if x["state"] == "Booted"))')" -derivedDataPath /tmp/FanStageiOSDerived CODE_SIGNING_ALLOWED=NO test > /tmp/fanstage-integration-test.log 2>&1
rg 'testLocalServerIntegration|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)' /tmp/fanstage-integration-test.log | tail -12
