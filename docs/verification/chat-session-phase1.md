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

## Phase 1B — 잔여 검증과 종료 판정

- 시작 HEAD: `9744396`. 검증한 코드·테스트 HEAD: `9cb220f3b4300ef3748824a7c1bcf043fc64db81`. 이후 문서 커밋은 실행 코드를 바꾸지 않는다.
- 환경: Xcode 26.6 (17F113), 부팅된 iPhone 17 Pro 시뮬레이터 iOS 26.5. 공유 스킴 `FanStage`를 사용하고 실행 시 부팅 기기를 조회했다.
- Phase 1 기준선·최종 단위·UI·서버·빌드·분석 로그와 결과가 남아 있으며 위 기존 기록의 집계와 일치한다. CH-01 수정 전 RED 로그도 확인했다.

### CH-01 UI: RED → FIX → PASS

- **RED:** `testPendingRecoveryAndDiscardUIWithServer`를 격리 서버·ACK 유실 프록시와 실행했을 때 Pending 중 뒤로 가기에 확인 안내가 없어 실패했다. 테스트 대상 `7728b16`, 로그 `/tmp/FanStagePhase1BRedUI.log`, 결과 `/tmp/FanStageiOSDerived/Logs/Test/Test-FanStage-2026.11.10_18-02-16-+0900.xcresult`. 기존 CH-01 연결 전 Pending RED는 위 Phase 1 기록을 보존한다.
- **FIX:** `26ad8ed`에서 Pending이 있으면 나가기 전 앱 종료 시 메모리 상태가 사라진다는 안내와 Stay/Leave 선택을 추가했다. 메시지 폐기는 기존 별도 확인을 따른다.
- **PASS:** 동일 UI 테스트에서 서버 연결과 Pending, 폐기 취소 후 동일 식별자, 동일 ID 재시도와 ACK 병합, 별도 메시지 폐기 확인, Pending 중 Connect 비활성·서버 전환 숨김, 나가기 취소 후 식별자 유지 및 재진입 후 복구를 확인했다. `testServerDraftRemainsBeforeConnection`도 연결 전 입력과 비활성 Send를 확인했다. 테스트 토큰은 격리 서버용 일회성 값이며 소스에 저장하지 않는다. 테스트용 주소·토큰은 Debug 앱 실행 환경으로 전달한다.

### CH-02/03: 결정적 회귀와 실제 소켓

- **CH-02 PASS:** 기존 `testDelayedReceiveAfterSuspendIsIgnored`, `testDelayedSubscriptionAfterSuspendIsIgnored`, `testDelayedSendCompletionAfterSuspendDoesNotStartDeadline`의 continuation 기반 검증을 보존했다. 추가 `testDelayedRealSocketDoesNotCorruptNewSessionWhenConfigured`는 로컬 소켓 서버가 첫 구독을 보류한 사실을 관측한 후 suspend·새 연결을 실행하고, 새 구독 성공 후 이전 서버 전송 시도를 해제해 현재 세대·상태·메시지·Pending·Deadline을 확인한다. 별도 격리 Android 서버 테스트에서 현재 연결의 ACK와 메시지를 확인했다. 서버의 `sendall` 성공은 취소된 소켓에 프레임이 실제 전달되었다는 증거가 아니다. 실제 HTTP 응답 지연 취소는 NOT_RUN.
- **CH-03 PASS:** `testRealSocketRetryLimitAndResetWhenConfigured`는 실제 핸드셰이크 요청을 계수해 연속 실패 6회에서 중단하고, 다섯 실패 후 여섯 번째 성공·단절 뒤에도 새 성공까지 재시도하는 것을 확인한다. 단절 자체도 실패로 한 번 집계되므로 두 번째 성공은 전체 11번째 요청이다. `testRealSocketSuspendStopsRetryWhenConfigured`는 각각 suspend·stop 이후 원래 대기 시간보다 긴 관찰 구간에서 추가 요청이 없음을 확인한다. 테스트 인스턴스만 `retrySleep`을 주입하며 기본 앱 정책은 바꾸지 않았다.
- CH-02·CH-03의 수정 전 RED는 **NOT_VERIFIED**다. 새 테스트는 수정 후의 수신·송신 및 대기 seam에 의존하여 기준 코드에 그대로 적용할 수 없으므로 과거 실패를 추정하지 않았다. 수정 후 실제 소켓 지연·시도 횟수와 결정적 회귀를 각각 기록한다.
- 소켓 횟수 fixture의 첫 실행 `/tmp/FanStagePhase1BSockets.xcresult`은 재구독 후 단절을 실패로 집계하는 실제 정책을 fixture가 누락해 실패했다. 해당 fixture의 예상 요청 순서를 교정하고 최종 재실행했다. 제품 재시도 정책을 이 실패에 맞춰 바꾸지 않았다.

### Phase 1B 최종 명령과 결과

공통 Xcode 인자: `-project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=<실행 시 조회한 UDID>' -derivedDataPath /tmp/FanStagePhase1BDerived CODE_SIGNING_ALLOWED=NO`.

| 명령 | 종료 코드와 결과 | 증거 |
|---|---|---|
| `xcodebuild <공통 인자> -resultBundlePath /tmp/FanStagePhase1BUnitFinal.xcresult -only-testing:FanStageTests test` | 0; PASS 14 / FAIL 0 / SKIP 6 | `/tmp/FanStagePhase1BUnitFinal.log`, `/tmp/FanStagePhase1BUnitFinal.xcresult`. SKIP: 서버 2, HLS 1, 별도 소켓 fixture 3 미설정 |
| `FANSTAGE_TEST_SELECTION='-only-testing:FanStageUITests' scripts/test-local-chat.sh` | 0; PASS 3 / FAIL 0 / SKIP 0 | `/tmp/FanStagePhase1BUICommittedXcode.log`, `/tmp/FanStageiOSDerived/Logs/Test/Test-FanStage-2026.11.10_18-11-44-+0900.xcresult` |
| `scripts/test-local-chat.sh` | 0; PASS 16 / FAIL 0 / SKIP 4 | `/tmp/FanStagePhase1BIntegrationFinalXcode.log`, `/tmp/FanStageiOSDerived/Logs/Test/Test-FanStage-2026.11.10_18-10-28-+0900.xcresult`. SKIP: HLS 1, 별도 소켓 fixture 3 미설정 |
| `scripts/test-phase1b-sockets.sh` | 0; PASS 17 / FAIL 0 / SKIP 3 | `/tmp/FanStagePhase1B.Tox0B0/xcodebuild.log`, `/tmp/FanStagePhase1B.Tox0B0/SocketTests.xcresult`. SKIP: Android 서버 2, HLS 1 미설정 |
| `xcodebuild <공통 인자> build` | 0; PASS | `/tmp/FanStagePhase1BBuild.log` |
| `xcodebuild <공통 인자> analyze` | 0; PASS | `/tmp/FanStagePhase1BAnalyze.log` |

서버·UI 테스트는 별도 로컬 Compose 프로젝트와 임시 자격값을 사용하고 기존 서버 설정을 변경하지 않았다. 생성한 테스트 DB 볼륨은 삭제하지 않았다. 위 각 테스트의 SKIP은 그 명령에서 검증하지 않았다는 뜻이며, 해당 범위는 별도 fixture 결과로 구분했다. HLS는 이번 단계에서 재검증하지 않았다.

**판정: VERIFIED**, 위 자동 검증 범위에 한정한다. 취소된 소켓에 이전 프레임이 실제로 전달됐는지, 실제 HTTP 응답 지연 취소와 장시간 누수는 위 한계대로 남는다. Phase 2는 진행하지 않았다.
