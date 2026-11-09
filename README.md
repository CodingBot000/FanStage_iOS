# FanStage iOS

Android FanStage를 SwiftUI로 이관하는 포트폴리오 프로젝트입니다. 현재 초기 구현 단계입니다.

- iOS 17 이상, iPhone 세로 방향
- 네 탭, 가상 게시물·메시지, 합성 영상과 Fake LIVE 채팅의 기본 화면
- 기존 백엔드 연동, HLS·플레이어 설정, 한국어 현지화, 접근성·화면 검증은 미완료

Xcode에서 `FanStage.xcodeproj`를 열어 iPhone 시뮬레이터를 선택하고 실행합니다. 가상 데이터는 메모리에만 보관됩니다. 합성 영상은 Android 프로젝트의 FFmpeg `testsrc2` 영상에서 변환했습니다. 아티스트 이미지는 기존 프로젝트의 생성형 이미지입니다. 기존 서버나 개인 MP4는 포함하지 않습니다.
