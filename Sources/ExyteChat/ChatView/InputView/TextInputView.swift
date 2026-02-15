//
//  Created by Alex.M on 14.06.2022.
//

import SwiftUI

struct TextInputView: View {

    @Environment(\.chatTheme) private var theme

    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @Binding var text: String
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInput: AvailableInputType

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                TextField("", text: $text, axis: .vertical)
                    .customFocus($globalFocusState.focus, equals: .uuid(inputFieldId))
            } else {
                LegacyMultilineTextField(
                    text: $text,
                    isFocused: Binding(
                        get: { globalFocusState.focus == .uuid(inputFieldId) },
                        set: { newValue in
                            if newValue {
                                globalFocusState.focus = .uuid(inputFieldId)
                            } else if globalFocusState.focus == .uuid(inputFieldId) {
                                globalFocusState.focus = nil
                            }
                        }
                    ),
                    textColor: UIColor(style == .message ? theme.colors.textLightContext : theme.colors.textDarkContext),
                    font: .systemFont(ofSize: 17)
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .placeholder(when: text.isEmpty) {
            Text(style.placeholder)
                .foregroundColor(theme.colors.buttonBackground)
        }
        .foregroundColor(style == .message ? theme.colors.textLightContext : theme.colors.textDarkContext)
        .padding(.vertical, 10)
        .padding(.leading, !availableInput.isMediaAvailable ? 12 : 0)
        .onTapGesture {
            globalFocusState.focus = .uuid(inputFieldId)
        }
    }
}

// MARK: - iOS 15 multiline text field fallback

private struct LegacyMultilineTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var textColor: UIColor
    var font: UIFont

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = font
        tv.textColor = textColor
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
        tv.textColor = textColor

        if isFocused && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFocused && tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }
    }
}
