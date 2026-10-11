import SwiftUI
import UIKit

/// UIKit이 소유한 marked text를 SwiftUI 상태 갱신이 조합 도중 되써서 깨뜨리지 않도록 하는 제목 입력기.
/// 입력값은 매번 Binding에 반영하되, 조합 중에는 외부 값을 UITextField로 다시 주입하지 않는다.
struct CompositionSafeTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        textField.placeholder = placeholder

        // markedTextRange가 있는 동안 text를 대입하면 한국어 조합 세션과 선택 영역이 초기화될 수 있다.
        guard textField.markedTextRange == nil, textField.text != text else { return }
        textField.text = text
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            // 한글 등 조합형 입력기가 조합 중(marked text)인 동안에는 그 중간값을 SwiftUI
            // 상태로 내보내지 않는다. 중간값을 Binding에 흘려보내면 SwiftUI body가 재평가되고
            // Form(List) 레이아웃이 다시 계산되는데, 바로 그 과정이 UITextField의 marked text
            // 조합 세션을 끊어 "ㄱㅗ기"처럼 자모가 분리되는 원인이 된다 — updateUIView 쪽만
            // 막아서는(SwiftUI→UIKit 역주입 방지) 부족했고, 이 반대 방향(UIKit→SwiftUI)도
            // 똑같이 막아야 한다. 조합이 끝나 확정된 텍스트만 반영한다.
            guard textField.markedTextRange == nil else { return }
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // 포커스를 잃으면 iOS가 조합을 자동 확정하므로 보통 이 시점엔 marked text가 없다.
            // 혹시 모를 불일치에 대비해 최종값을 한 번 더 동기화하는 안전장치다.
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// 제목과 같은 동기화 원칙을 사용하는 여러 줄 메모 입력기.
struct CompositionSafeTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text

        guard textView.markedTextRange == nil, textView.text != text else { return }
        textView.text = text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            // 제목 입력기와 동일한 이유로, 조합 중간값은 SwiftUI 상태로 내보내지 않는다.
            guard textView.markedTextRange == nil else { return }
            text.wrappedValue = textView.text
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
