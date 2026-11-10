# iOS 채팅 후보정 현황

- **Phase 1: VERIFIED (scope-limited)** — Phase 1B의 지정된 자동 검증을 통과했다. 아래 범위와 한계에 한정한다.
- Phase 1 기준 HEAD: `3a580eebc9ae38ecd2ae91821cc01f9ec5ed2f5a`
- Phase 1B 시작 HEAD: `9744396`
- 마지막으로 검증한 코드·테스트 커밋: `9cb220f3b4300ef3748824a7c1bcf043fc64db81`

| 항목 | 상태 | 확인 범위 |
|---|---|---|
| CH-01 연결 전·Pending | VERIFIED | 입력 보존, 연결 후 Pending·ACK, 폐기 취소·확정, 나가기 경고와 취소, 대상 변경 차단 및 재진입 복구를 격리 서버를 이용한 UI 테스트로 확인 |
| CH-02 늦은 응답·송신 완료 | VERIFIED | continuation으로 이전 세대 ACK·구독·송신 완료를 지연해 차단하고, 실제 소켓의 구독 프레임 대기 중 중단·새 연결과 최신 서버 메시지 수신을 확인. 취소된 소켓에 늦은 프레임이 실제 전달됐는지는 확인할 수 없음 |
| CH-03 연속 실패 | VERIFIED | 실제 루프백 소켓에서 연속 실패 6회 상한, 구독 성공 후 재접속 정책 초기화, suspend·stop 후 추가 시도 없음을 관찰. 테스트에서만 대기 시간을 주입 |

- [x] 기존 단위 테스트 기준 결과와 CH-01 RED 확인
- [x] Pending 폐기·재연결 UI 경로와 나가기 확인 검증
- [x] 실제 소켓의 지연·취소 경계와 최신 연결 검증
- [x] 실제 소켓 재접속 횟수·중단 검증
- [x] 시뮬레이터 단위·UI, 격리 서버 통합, 빌드·분석 실행

CH-02·CH-03의 **수정 전 RED는 NOT_VERIFIED**다. 실제 HTTP 조회 응답 지연과 오래된 소켓 프레임이 취소된 클라이언트에 실제 전달되는 상황, 장시간 리소스 누수는 별도 검증이 필요하다. 미확정 메시지는 앱 실행 중 메모리에만 존재한다. 테스트용 격리 DB 볼륨은 자동 삭제하지 않았다. [명령·결과·한계](verification/chat-session-phase1.md)

Phase 2는 사용자 승인 후 책임 분리와 네트워크 경계 테스트 구조를 검토한다. 구현은 시작하지 않았다.

## Phase 2

- **VERIFIED** — 시작 HEAD `1c399b4`; 검증한 코드·테스트 커밋 `fbdaaf1c67e48dc1232735ca1da11d7b3c59ed6f`.
- [x] 기준선·계약 확인 및 `ChatTimeline` 분리
- [x] `ChatTransport`/`URLSessionChatTransport`와 제어 가능한 Fake 분리
- [x] Phase 1 단위·UI·기존 서버·실소켓 회귀, build/analyze
- [x] Fake HTTP 지연 취소 검증 (SIMULATED_PASS)
- 실제 HTTP 지연 취소, 취소 소켓에 대한 지연 프레임의 실제 전달, 장시간 리소스 누수는 NOT_VERIFIED다. 세부 결과는 [Phase 2 검증](verification/chat-session-phase2.md)에 기록한다.
- Phase 3 후보는 장시간 리소스 관찰과 실제 네트워크 지연 검증이다. 구현은 시작하지 않았다.
