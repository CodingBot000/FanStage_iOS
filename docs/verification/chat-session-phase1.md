# ChatSession Phase 1 검증 기록

- 기준 HEAD: `3a580eebc9ae38ecd2ae91821cc01f9ec5ed2f5a`. 지시서 기준 `8df35db` 이후 변경은 README와 스크린샷이며, 이력 재작성으로 커밋 ID가 변경되었다. `git diff --stat 8df35db HEAD`로 확인했다.
- 환경: Xcode 26.6 (17F113), iPhone 17 Pro 시뮬레이터, iOS 26.5.
- 기준 실행: `xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=353852C5-1973-4E5E-8880-344F32A7BCD2' -derivedDataPath /tmp/FanStagePhase1Derived -resultBundlePath /tmp/FanStagePhase1Baseline.xcresult CODE_SIGNING_ALLOWED=NO -only-testing:FanStageTests test`.
- 기준 결과: PASS 5, FAIL 0, SKIP 3. SKIP은 격리 서버 2개와 HLS 1개가 미설정된 조건이다. 로그 `/tmp/FanStagePhase1Baseline.log`, 결과 `/tmp/FanStagePhase1Baseline.xcresult`.
- Phase 1 진행 중. 아래 결과는 실제 실행 후 갱신한다.

## RED

- CH-01 `testUnboundSessionDoesNotEnqueueMessage`: FAIL 1/1, 기존 코드가 연결 대상 없이 Pending을 생성함. `/tmp/FanStagePhase1Red.log`, `/tmp/FanStagePhase1Red.xcresult`.
- CH-02 / CH-03: 기존 코드에 비동기 수신·전송 완료와 재연결 실패를 제어하는 seam이 없어 RED NOT_VERIFIED. seam 추가 후 결정적 회귀 검증을 수행한다.
