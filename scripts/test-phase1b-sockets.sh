#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
if lsof -iTCP:28768 -sTCP:LISTEN -t >/dev/null; then echo 'Test port unavailable'; exit 1; fi
sim_id="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for ds in d["devices"].values() for x in ds if x["state"] == "Booted" and x["name"].startswith("iPhone")))')"
run_dir="$(mktemp -d /tmp/FanStagePhase1B.XXXXXX)"
python3 "$repo_dir/scripts/phase1b-socket-fixture.py" > "$run_dir/fixture.log" 2>&1 &
fixture_pid=$!
cleanup() { xcrun simctl spawn "$sim_id" launchctl unsetenv FANSTAGE_PHASE1B_FIXTURE || true; kill "$fixture_pid" 2>/dev/null || true; }
trap cleanup EXIT
for i in {1..100}; do if curl -fsS http://127.0.0.1:28768/stats >/dev/null 2>&1; then break; fi; sleep 0.05; done
curl -fsS http://127.0.0.1:28768/stats >/dev/null
xcrun simctl spawn "$sim_id" launchctl setenv FANSTAGE_PHASE1B_FIXTURE http://127.0.0.1:28768
xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination "platform=iOS Simulator,id=$sim_id" -derivedDataPath "${FANSTAGE_DERIVED_DATA:-/tmp/FanStagePhase1BDerived}" -resultBundlePath "$run_dir/SocketTests.xcresult" CODE_SIGNING_ALLOWED=NO -only-testing:FanStageTests test > "$run_dir/xcodebuild.log" 2>&1
printf 'Artifacts: %s\n' "$run_dir"
rg 'testRealSocket|testDelayedRealSocket|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)' "$run_dir/xcodebuild.log" | tail -14
