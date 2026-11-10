# Phase 2 채팅 책임 분리 검증

- 시작 브랜치 `fix/ios-chat-recovery-phase1`, HEAD `1c399b4`; 작업 트리 변경 없음.
- 환경: Xcode 26.6, iPhone 17 Pro 시뮬레이터 iOS 26.5. 기존 Phase 1 검증과 실제 HTTP 지연·장시간 누수의 제한은 [Phase 1 기록](chat-session-phase1.md)을 따른다.
- 상태: IN_PROGRESS. 전체 UI·격리 서버·실제 소켓·build/analyze는 리팩토링 완료 후 재실행한다.

## 기존 책임

| 책임 | 현재 필드·메서드 |
|---|---|
| UI 상태 | `messages`, `pending`, `status`, `serverMode`, `gapUnresolved`, `send`, `retry`, `discard` |
| 메시지 정합성 | `rows`, `cursor`, `highest`, `merge`, `scheduleRecovery`의 병합 |
| 네트워크 I/O | `socket`, `URLSession`, 프레임 디코딩, `transmit`, HTTP 요청 |
| 수명주기 | `epoch`, `worker`, `recovery`, `deadlines`, `stop`, `suspend`, `reconnect` |

## 계약 체크리스트

- [ ] Fake/UI·입력 및 Pending 보존: `testServerDraftRemainsBeforeConnection`, `testPendingRecoveryAndDiscardUIWithServer`
- [ ] CH-01 바인딩·전환·ID: `testUnboundSessionDoesNotEnqueueMessage`, `testBoundPendingCannotSwitchAccountOrBeClearedByStop`, `testRoomSessionRetainsPendingAcrossNavigation`
- [ ] CH-02 이전 세대 이벤트·송신: `testDelayedReceiveAfterSuspendIsIgnored`, `testDelayedSendCompletionAfterSuspendDoesNotStartDeadline`, `testDelayedRealSocketDoesNotCorruptNewSessionWhenConfigured`
- [ ] CH-03 재연결·중단: `testRetryPolicyResetsOnSubscriptionAndStopsAtLimit`, `testRealSocketRetryLimitAndResetWhenConfigured`, `testRealSocketSuspendStopsRetryWhenConfigured`
- [ ] 서버 ACK 멱등·재전송: `testLostAcknowledgementWhenConfigured`, `testLocalServerIntegrationWhenConfigured`
- [ ] 중복·역순·gap·늦은 조회와 이전 룸 분리: 기존 `testChatOrdersAndDeduplicatesAndIgnoresOtherRooms`, 추가 결정적 테스트 필요
- [ ] 자원 해제 및 기존 UI·서버 계약 유지: 기존 전체 회귀 및 코드 리뷰

## 기준 실행

`xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=<실행 시 조회한 부팅 기기>' -derivedDataPath /tmp/FanStagePhase2Derived -resultBundlePath /tmp/FanStagePhase2Baseline.xcresult CODE_SIGNING_ALLOWED=NO -only-testing:FanStageTests test`: 종료 0, PASS 14 / FAIL 0 / SKIP 6 (서버·소켓·HLS fixture 미설정). 로그 `/tmp/FanStagePhase2Baseline.log`, 결과 `/tmp/FanStagePhase2Baseline.xcresult`.

## P2-03 타임라인 분리

`ChatTimeline`으로 룸·순번·연속 커서·최대 순번·표시 한도를 이동했다. Pending ACK 해소는 `ChatSession`에 유지한다. `testTimelineMergesLateBackfillWithoutLosingNewEvents`로 1→3→4→지연 2, 중복 및 다른 룸을 확인했다. 첫 빌드는 `ChatTimeline` 초기화 접근 오류로 실패했고 초기화자를 명시한 후 재실행했다. `/tmp/FanStagePhase2Timeline.log` FAIL, `/tmp/FanStagePhase2Timeline2.log` PASS 15 / FAIL 0 / SKIP 6; `/tmp/FanStagePhase2Timeline2.xcresult`.

## P2-03 Transport 경계

`ChatTransport`/`ChatConnection`과 `URLSessionChatTransport`로 WebSocket·HTTP 요청 및 직렬화 책임을 이동했다. `ChatSession`은 연결 식별과 세대 검증 및 UI 상태를 소유한다. 테스트용 Fake로 늦은 HTTP, 새 이벤트 이후 누락 보충, 이전 연결 이벤트 및 늦은 송신 완료를 제어한다. `/tmp/FanStagePhase2Fake3.log`와 `/tmp/FanStagePhase2Fake3.xcresult`: PASS 19 / FAIL 0 / SKIP 6. 이전 빌드 디렉터리 재사용 실행은 최신 Fake 테스트가 검색되지 않아 최종 근거로 쓰지 않고 새 디렉터리로 재실행했다. 실제 네트워크의 HTTP 지연 취소는 이 Fake 테스트로 증명되지 않는다.

통합 스크립트는 기존 기본 경로를 유지하면서 `FANSTAGE_DERIVED_DATA`로 격리된 빌드 경로를 지정할 수 있도록 했다. 목적은 오래된 XCTest 검색 결과를 재사용하지 않고 실제 최신 테스트 목록을 확인하는 것이다.

## 통합 검증 진행

변경 후 `FANSTAGE_DERIVED_DATA=/tmp/FanStagePhase2SocketFresh scripts/test-phase1b-sockets.sh`: 종료 0, PASS 22 / FAIL 0 / SKIP 3(기존 서버 2, HLS 1), 결과 `/tmp/FanStagePhase1B.Rquh0e/SocketTests.xcresult`, 로그 `/tmp/FanStagePhase2SocketRun.log`. `FANSTAGE_DERIVED_DATA=/tmp/FanStagePhase2ServerFresh scripts/test-local-chat.sh`: 종료 0, PASS 21 / FAIL 0 / SKIP 4(HLS 1, 별도 소켓 fixture 3), 로그 `/tmp/FanStagePhase2ServerXcode.log`. 기존 서버의 ACK 유실·동일 ID 재전송 및 DB 행 하나를 실행했다. UI 전체·최종 build/analyze 진행 중.

## 완료 구조와 계약 검증

최종 코드·테스트 기준 `fbdaaf1`.

- `ChatSession`: UI 상태, 룸별 Pending·Deadline, 세대와 재연결·복구 orchestration. `URLSessionWebSocketTask`, 프레임 디코딩, HTTP URL/헤더·파싱은 직접 소유하지 않는다.
- `ChatTransport`/`ChatConnection`: 비동기 수신·전송·종료·조회 계약. `URLSessionChatTransport`가 기존 WebSocket/HTTP 경로·Bearer 인증 및 frame 크기 검사를 처리한다. `FakeChatTransport`는 수신·조회·송신 지연과 오류를 제어한다.
- `ChatTimeline`: 서버 순번·중복·gap·기존 표시/보관 한도를 네트워크 없이 관리한다. Pending 해소는 Session 한 곳에 남긴다. 별도 패키지나 외부 의존성은 추가하지 않았다.

| 계약 | 테스트와 수준 |
|---|---|
| CH-01 입력 보존·Pending·대상 변경·동일 ID·폐기 | `testUnboundSessionDoesNotEnqueueMessage`, `testBoundPendingCannotSwitchAccountOrBeClearedByStop`, `testRoomSessionRetainsPendingAcrossNavigation`, `testPendingRecoveryAndDiscardUIWithServer` (단위·격리 서버 UI) |
| CH-02 늦은 이벤트·송신·새 연결 | `testFakeTransportIgnoresOldConnectionEvent`, `testFakeTransportLateSendCompletionDoesNotRestartDeadline`, 기존 continuation 및 `testDelayedRealSocketDoesNotCorruptNewSessionWhenConfigured` (Fake·실소켓) |
| CH-03 연속 실패·성공 초기화·취소 | `testRetryPolicyResetsOnSubscriptionAndStopsAtLimit`, `testRealSocketRetryLimitAndResetWhenConfigured`, `testRealSocketSuspendStopsRetryWhenConfigured`, `testFakeTransportFailureAndCancellationDoNotOpenAnotherSocket` (단위·Fake·실소켓) |
| 정렬·중복·gap·룸 | `testChatOrdersAndDeduplicatesAndIgnoresOtherRooms`, `testTimelineMergesLateBackfillWithoutLosingNewEvents`, `testFakeTransportLateBackfillMergesNewerEvent` (단위·Fake) |
| HTTP 지연·취소 | `testFakeTransportCancelledLateHTTPDoesNotAlterNewSession`: SIMULATED_PASS. Task 완료를 기다려 새 세션이 이전 조회 응답에 오염되지 않음을 확인. REAL_HTTP_NOT_VERIFIED |
| 동일 ID·서버 저장 | `testLostAcknowledgementWhenConfigured`, `testLocalServerIntegrationWhenConfigured` (기존 격리 서버) |

기존 Pending UI·서버·socket 테스트는 비활성화하지 않았다. 첫 타임라인 컴파일 실패 및 기존 빌드 디렉터리의 오래된 테스트 검색 문제는 위 작업 과정에 기록했다.

## 코드 리뷰와 제한

지연 HTTP 테스트가 Fake 응답 해제 후 고정 횟수의 `Task.yield()`만 사용해 복구 Task 완료를 보장하지 않는 점을 확인했다. `recoveryTaskForTesting`으로 실제 완료를 기다리도록 보완하고 회귀를 재실행했다. 이전 transport/세대 검증은 frame 적용 전과 송신·HTTP await 이후에 확인했다. 별도의 신규 기능 결함은 이 범위의 리뷰에서 관찰하지 못했다. 송신 Task는 기존처럼 비구조화되어 소켓 닫기와 세대 검사로 결과를 차단하며, 장시간 누수는 측정하지 않았다. 취소된 실제 소켓의 지연 프레임 전달과 실제 HTTP 지연 취소는 여전히 확인하지 못했다. 기초 빌드와 최종 build/analyze 로그에서 새 actor isolation/Sendable 경고는 확인되지 않았으며, Swift 언어 모드는 바꾸지 않았다.

## 최종 검증 결과

실행일 2026-11-11, Xcode 26.6 (17F113), 부팅된 iPhone 17 Pro 시뮬레이터 iOS 26.5. 최종 코드·테스트 커밋 `fbdaaf1c67e48dc1232735ca1da11d7b3c59ed6f`; 이후 문서 커밋은 실행 코드를 바꾸지 않는다. 각 명령은 부팅된 iPhone UDID를 실행 시 조회했다.

| 명령 | 종료 코드·결과 | 로그·결과 |
|---|---|---|
| `xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=<부팅 기기>' -derivedDataPath /tmp/FanStagePhase2VerifiedFresh -resultBundlePath /tmp/FanStagePhase2VerifiedUnit.xcresult CODE_SIGNING_ALLOWED=NO -only-testing:FanStageTests test` | 0; PASS 20 / FAIL 0 / SKIP 6 | `/tmp/FanStagePhase2VerifiedUnit.log`, `/tmp/FanStagePhase2VerifiedUnit.xcresult`. SKIP은 서버 2, 소켓 fixture 3, HLS 1 미설정 |
| `FANSTAGE_DERIVED_DATA=/tmp/FanStagePhase2VerifiedFresh FANSTAGE_TEST_SELECTION='-only-testing:FanStageUITests' scripts/test-local-chat.sh` | 0; PASS 3 / FAIL 0 / SKIP 0 | `/tmp/FanStagePhase2VerifiedUIXcode.log`, `/tmp/FanStagePhase2VerifiedFresh/Logs/Test/Test-FanStage-2026.11.11_00-52-45-+0900.xcresult` |
| `FANSTAGE_DERIVED_DATA=/tmp/FanStagePhase2VerifiedFresh scripts/test-local-chat.sh` | 0; PASS 22 / FAIL 0 / SKIP 4 | `/tmp/FanStagePhase2VerifiedServerXcode.log`, `/tmp/FanStagePhase2VerifiedFresh/Logs/Test/Test-FanStage-2026.11.11_00-52-00-+0900.xcresult`. SKIP은 소켓 fixture 3, HLS 1 |
| `FANSTAGE_DERIVED_DATA=/tmp/FanStagePhase2VerifiedFresh scripts/test-phase1b-sockets.sh` | 0; PASS 23 / FAIL 0 / SKIP 3 | `/tmp/FanStagePhase2VerifiedSocket.log`, `/tmp/FanStagePhase1B.CNojBL/SocketTests.xcresult`. SKIP은 Android 서버 2, HLS 1 |
| `xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=<부팅 기기>' -derivedDataPath /tmp/FanStagePhase2VerifiedFresh CODE_SIGNING_ALLOWED=NO build` | 0; PASS | `/tmp/FanStagePhase2VerifiedBuild.log` |
| `xcodebuild -project FanStage.xcodeproj -scheme FanStage -destination 'platform=iOS Simulator,id=<부팅 기기>' -derivedDataPath /tmp/FanStagePhase2VerifiedFresh CODE_SIGNING_ALLOWED=NO analyze` | 0; PASS | `/tmp/FanStagePhase2VerifiedAnalyze.log` |

서로 다른 명령에서 반복 실행한 테스트는 독립 테스트 수로 합산하지 않았다. SKIP 범위 중 서버와 실제 소켓은 각 별도 실행에서 확인했고 HLS는 이번 변경 범위 밖이라 재실행하지 않았다. 서버는 격리 Compose 프로젝트를 사용했으며 볼륨은 삭제하지 않았다.

**Phase 2 판정: VERIFIED.** 다만 실제 취소 소켓으로 지연 프레임이 전달되는 상황, 실제 HTTP 지연 취소 및 장시간 리소스 누수는 NOT_VERIFIED이며 위 Fake·실소켓 결과가 이를 증명하지 않는다. Phase 3 구현·원격 푸시·PR·병합은 수행하지 않았다.
