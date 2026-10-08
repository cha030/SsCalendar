import EventKit
import EventKitUI
import SwiftUI
import UIKit

/// 시스템 일정 상세 시트에 넘길 값. 같은 일정을 다시 열어도 새 시트로 표시되도록 고유 ID를 둔다.
struct SystemEventPresentation: Identifiable {
    let id = UUID()
    let event: EKEvent
    let allowsEditing: Bool
}

/// Apple 기본 일정 상세 화면(EKEventViewController).
/// 수정·삭제와 반복 일정의 "이 이벤트만 / 이후 모든 이벤트" 선택은 Apple UI가 직접 처리한다.
/// 따라서 반드시 사용자가 탭한 발생분(EKEvent)을 넘겨야 한다.
struct SystemEventDetailView: UIViewControllerRepresentable {
    let presentation: SystemEventPresentation
    let onComplete: (EKEventViewAction) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = presentation.event
        // 읽기 전용 캘린더(구독·생일 등)는 Edit 버튼 없이 보기만 허용한다.
        controller.allowsEditing = presentation.allowsEditing
        controller.delegate = context.coordinator
        // Done·Edit 버튼은 내비게이션 바에 표시되므로 내비게이션 컨트롤러로 감싼다.
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        var onComplete: (EKEventViewAction) -> Void

        init(onComplete: @escaping (EKEventViewAction) -> Void) {
            self.onComplete = onComplete
        }

        func eventViewController(
            _ controller: EKEventViewController,
            didCompleteWith action: EKEventViewAction
        ) {
            onComplete(action)
        }
    }
}
