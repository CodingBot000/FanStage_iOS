# ChatSession Phase 1 검증 기록

- 기준 HEAD: `3a580eebc9ae38ecd2ae91821cc01f9ec5ed2f5a`. 지시서 기준 `8df35db` 이후 변경은 README와 스크린샷이며, 이력 재작성으로 커밋 ID가 변경되었다. `git diff --stat 8df35db HEAD`로 확인했다.
- 환경: Xcode 26.6 (17F113), iPhone 17 Pro 시뮬레이터, iOS 26.5.
- 기준 실행: `xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=353852C5-1973-4E5E-8880-344F32A7BCD2' -derivedDataPath /tmp/FanStagePhase1Derived -resultBundlePath /tmp/FanStagePhase1Baseline.xcresult CODE_SIGNING_ALLOWED=NO -only-testing:FanStageTests test`.
- 기준 결과: PASS 5, FAIL 0, SKIP 3. SKIP은 격리 서버 2개와 HLS 1개가 미설정된 조건이다. 로그 `/tmp/FanStagePhase1Baseline.log`, 결과 `/tmp/FanStagePhase1Baseline.xcresult`.
- Phase 1 진행 중. 아래 결과는 실제 실행 후 갱신한다.

## RED

- CH-01 `testUnboundSessionDoesNotEnqueueMessage`: FAIL 1/1, 기존 코드가 연결 대상 없이 Pending을 생성함. `/tmp/FanStagePhase1Red.log`, `/tmp/FanStagePhase1Red.xcresult`.
- CH-02 / CH-03: 기존 코드에 비동기 수신·전송 완료와 재연결 실패를 제어하는 seam이 없어 RED NOT_VERIFIED. seam 추가 후 결정적 회귀 검증을 수행한다.

## 변경과 GREEN

검증한 구현 커밋: `792e7e63bf57833b54bd748b3fda60f42b78a766`. 이후 문서 전용 커밋은 실행 대상 코드를 바꾸지 않는다.

- CH-01: 연결 대상이 없는 `send`를 거절하고 UI 입력을 유지한다. 바인딩된 일시 중단 세션은 기존 ID를 보존한다. Pending이 있으면 설정 변경·완전 종료로 토큰을 교체하지 않고, 명시적 확인 후에만 폐기한다. `testUnboundSessionDoesNotEnqueueMessage`, `testBoundPendingCannotSwitchAccountOrBeClearedByStop`, `testRoomSessionRetainsPendingAcrossNavigation`, `testPendingDiscardRequiresConfirmation`, `testServerDraftRemainsBeforeConnection` PASS. 기존 두 테스트는 정책 변경에 맞춰 테스트용 로컬 주소에 먼저 바인딩하도록 수정했다. 폐기 확인 대화상자·재연결 버튼의 실제 Pending UI 경로는 NOT_RUN.
- CH-02: 수신 await 이후 세대와 취소 상태를 확인하고, 전송 완료 뒤 현재 소켓·세대와 Pending 존재를 확인한다. HTTP 조회 완료 후 취소·세대를 확인한다. `testCancelledGenerationRejectsOldAckAndSubscription`, `testDelayedReceiveAfterSuspendIsIgnored`, `testDelayedSubscriptionAfterSuspendIsIgnored`, `testDelayedSendCompletionAfterSuspendDoesNotStartDeadline` PASS. 제어 가능한 continuation을 사용해 await 중 suspend를 재현한다. 실제 네트워크 지연 주입은 NOT_RUN; 기존 코드에서의 RED는 NOT_VERIFIED.
- CH-03: `ChatReconnectPolicy`는 유효한 subscribed 이후 연속 실패 수를 초기화하고, 6회 연속 실패에서 중단한다. `testRetryPolicyResetsOnSubscriptionAndStopsAtLimit`, `testSuspendedReconnectDoesNotChangeStatus` PASS. 실제 소켓 시도 횟수 계측은 NOT_RUN; 기존 코드에서의 RED는 NOT_VERIFIED. 백그라운드 이행 시 `PlaybackView`가 채팅을 중단하고 복귀 시 바인딩된 세션을 재연결한다. 이 화면 수명주기 경로 자체의 UI 자동 검증은 NOT_RUN.
- 미확정 전송이 있을 때 `stop()`은 대상·토큰을 바꾸지 않고 `suspend()`한다. 서로 다른 서버나 토큰으로 기존 메시지를 자동 이관하지 않는다. 기존 Android 서버 계약과 프로토콜은 변경하지 않았다.

## 최종 실행 결과

공통 Xcode 인자: `-project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=353852C5-1973-4E5E-8880-344F32A7BCD2' -derivedDataPath /tmp/FanStagePhase1Derived CODE_SIGNING_ALLOWED=NO`.

| 명령 | 결과 | 증거 |
|---|---|---|
| `xcodebuild <공통 인자> -resultBundlePath /tmp/FanStagePhase1UnitFinal2.xcresult -only-testing:FanStageTests test` | PASS 14, FAIL 0, SKIP 3 | `/tmp/FanStagePhase1UnitFinal2.log`, `/tmp/FanStagePhase1UnitFinal2.xcresult` |
| `xcodebuild <공통 인자> -resultBundlePath /tmp/FanStagePhase1UICommitted.xcresult -only-testing:FanStageUITests test` | PASS 2, FAIL 0, SKIP 0 | `/tmp/FanStagePhase1UICommitted.log`, `/tmp/FanStagePhase1UICommitted.xcresult` |
| `scripts/test-local-chat.sh` | PASS 16, FAIL 0, SKIP 1 (HLS); 격리 서버와 ACK 유실 포함 | `/tmp/FanStagePhase1IntegrationFinal.log`, `/tmp/fanstage-integration-test.log`, `/tmp/FanStageiOSDerived/Logs/Test/Test-FanStage-2026.11.10_17-46-08-+0900.xcresult` |
| `xcodebuild <공통 인자> build` | PASS | `/tmp/FanStagePhase1BuildFinal.log` |
| `xcodebuild <공통 인자> analyze` | PASS | `/tmp/FanStagePhase1AnalyzeFinal.log` |

UI 테스트 작성 중 `FanStagePhase1UI`·`UI2`·`UI3`·`UI4`·`UI5`·`UI6`은 스위치 접근성 탭 좌표가 설정 접기 영역에 닿아 실패했다. `UI7`에서 스위치 오른쪽을 탭한 단일 회귀가 PASS했고 최종 UI 전체 재실행에서 두 테스트가 PASS했다. 로그와 xcresult는 `/tmp/FanStagePhase1UI*.log`, `/tmp/FanStagePhase1UI*.xcresult`에 있다. 실패를 기존 기준 실패로 분류하지 않는다.

HLS 통합 테스트는 이 단계 범위 밖으로 재실행하지 않았다. 이전 HLS 결과는 README의 과거 기록이며 이번 변경의 신규 검증이 아니다. 서버 통합은 별도 Compose 프로젝트에서 실행했으며 테스트 볼륨은 삭제하지 않았다. Phase 1은 위 미실행 필수 경로 때문에 **PARTIAL**이다.
