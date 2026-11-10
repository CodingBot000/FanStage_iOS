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
