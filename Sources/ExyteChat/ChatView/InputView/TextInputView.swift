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

    @State private var legacyTextHeight: CGFloat = 34

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                TextField("", text: $text, axis: .vertical)
                    .customFocus($globalFocusState.focus, equals: .uuid(inputFieldId))
            } else {
                LegacyMultilineTextField(
                    text: $text,
                    textHeight: $legacyTextHeight,
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
                .frame(height: legacyTextHeight)
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
// Approach from https://shadowfacts.net/2020/swiftui-expanding-text-view/

private struct LegacyMultilineTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
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

        // Recalculate height after any update
        recalculateHeight(tv)
    }

    private func recalculateHeight(_ tv: UITextView) {
        let newSize = tv.sizeThatFits(CGSize(width: tv.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = max(newSize.height, font.lineHeight)
        if textHeight != newHeight {
            DispatchQueue.main.async {
                textHeight = newHeight
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, textHeight: $textHeight, font: font)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var textHeight: CGFloat
        let font: UIFont

        init(text: Binding<String>, textHeight: Binding<CGFloat>, font: UIFont) {
            _text = text
            _textHeight = textHeight
            self.font = font
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            let newSize = textView.sizeThatFits(
                CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude)
            )
            let newHeight = max(newSize.height, font.lineHeight)
            if textHeight != newHeight {
                textHeight = newHeight
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // isFocused is handled via the binding in updateUIView
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // isFocused is handled via the binding in updateUIView
        }
    }
}
