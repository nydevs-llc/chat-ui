//
//  SwiftUIView.swift
//  
//
//  Created by Alex.M on 07.07.2022.
//

import SwiftUI

struct MessageTextView: View {
    let text: String?
    let messageUseMarkdown: Bool
    let inbound: Bool
    let anyLinkColor: Color
    let darkLinkColor: Color
    let isDeleted: Bool
    let isStreaming: Bool
    let onMentionTap: ((String) -> Void)?

    @State private var showLinkOptions = false
    @State private var linkOptions: [LinkOption] = []

    private let computedAttributed: AttributedString?

    private static func makeBaseUIFont(isDeleted: Bool) -> UIFont {
        let base = isDeleted ? UIFont.systemFont(ofSize: 15) : UIFont.systemFont(ofSize: 17)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    private let baseUIFont: UIFont

    init(
        text: String?,
        messageUseMarkdown: Bool,
        inbound: Bool,
        anyLinkColor: Color,
        darkLinkColor: Color,
        isDeleted: Bool,
        isStreaming: Bool = false,
        onMentionTap: ((String) -> Void)?
    ) {
        self.text = text
        self.messageUseMarkdown = messageUseMarkdown
        self.inbound = inbound
        self.anyLinkColor = anyLinkColor
        self.darkLinkColor = darkLinkColor
        self.isDeleted = isDeleted
        self.isStreaming = isStreaming
        self.onMentionTap = onMentionTap

        let font = Self.makeBaseUIFont(isDeleted: isDeleted)
        self.baseUIFont = font

        if messageUseMarkdown, let t = text, !t.isEmpty {
            let processor = MarkdownProcessor(
                text: t,
                inbound: inbound,
                anyLinkColor: anyLinkColor,
                darkLinkColor: darkLinkColor,
                baseFont: font
            )
            self.computedAttributed = processor.formattedAttributedString()
        } else {
            self.computedAttributed = nil
        }
    }

    var body: some View {
        Group {
            if let text = text, !text.isEmpty {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    contentView(for: text)
                    if isStreaming {
                        StreamingCursorView()
                    }
                }
                .confirmationDialog(
                    dialogTitle(),
                    isPresented: $showLinkOptions,
                    titleVisibility: .visible
                ) {
                    ForEach(linkOptions) { option in
                        Button(option.displayName) { _ = handleLinkTap(option.url) }
                    }
                    Button("Скасувати", role: .cancel) { }
                }
                .animation(nil, value: computedAttributed)
            }
        }
    }

    @ViewBuilder
    private func contentView(for raw: String) -> some View {
        if messageUseMarkdown {
            if isDeleted {
                retractedMessage(attributedText: computedAttributed ?? AttributedString(raw))
            } else {
                Text(computedAttributed ?? AttributedString(raw))
                    .font(.system(size: baseUIFont.pointSize))
                    .fixedSize(horizontal: false, vertical: true)
                    .highPriorityGesture(TapGesture().onEnded {
                        handleTap(in: computedAttributed ?? AttributedString(raw))
                    })
            }
        } else {
            Text(raw)
                .font(.system(size: baseUIFont.pointSize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dialogTitle() -> String {
        linkOptions.allSatisfy({ $0.type.isMention }) ? "Оберіть користувача:" : "Оберіть посилання:"
    }

    @discardableResult
    private func handleLinkTap(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == "mention", let userID = url.host {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onMentionTap?(userID) }
            return .handled
        } else if let scheme = url.scheme, ["http", "https"].contains(scheme) {
            UIApplication.shared.open(url); return .handled
        } else {
            return .systemAction
        }
    }

    private func handleTap(in attributed: AttributedString) {
        let options: [LinkOption] = attributed.runs.compactMap { run in
            guard let url = run.link else { return nil }
            let display = String(attributed[run.range].characters)
            let type: LinkOption.LinkType = url.scheme == "mention" ? .mention(id: url.host ?? "") : .url
            return LinkOption(displayName: display, url: url, type: type)
        }
        if options.count == 1 {
            _ = handleLinkTap(options[0].url)
        } else if options.count > 1 {
            linkOptions = options
            showLinkOptions = true
        }
    }
}

struct LinkOption: Identifiable, Hashable, Equatable {
    enum LinkType: Hashable {
        case mention(id: String)
        case url

        var isMention: Bool {
            if case .mention = self { return true }
            return false
        }
    }

    let id = UUID()
    let displayName: String
    let url: URL
    let type: LinkType

    var userID: String? {
        if case .mention(let id) = type {
            return id
        }
        return nil
    }
}

extension MessageTextView {
    @ViewBuilder
    private func retractedMessage(attributedText: AttributedString) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "nosign")
                .foregroundColor(inbound ? .gray : Color.white.opacity(0.85))
                .font(.system(size: 14, weight: .semibold))
            
            Text(attributedText)
                .foregroundColor(inbound ? .gray : Color.white.opacity(0.85))
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.clear)
    }
}

private struct StreamingCursorView: View {
    @State private var isVisible = true

    var body: some View {
        Text("▌")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isVisible)
            .onAppear { isVisible = false }
    }
}

//struct MessageTextView_Previews: PreviewProvider {
//    static var previews: some View {
//        MessageTextView(text: "Hello world!", messageUseMarkdown: false, inbound: true, anyLinkColor: .blue, darkLinkColor: .blue)
//    }
//}

/// Многострочный текст шириной по самой длинной строке, а не по всей предложенной
/// ширине.
///
/// SwiftUI `Text` при переносе занимает ВСЮ предложенную ширину, хотя самая длинная
/// строка короче: справа в пузыре оставалась пустая полоса, тем шире, чем раньше
/// перенос (эмодзи широкие и переносят слово раньше — отсюда «баг длины сообщений с
/// эмодзи», Лев 17.10, A7). Telegram подгоняет пузырь под текст. Однострочный текст и
/// так узкий — его не трогаем. На iOS 15 (нет `Layout`) — как раньше.
struct TightTextWidth<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            TightTextWidthLayout { content }
        } else {
            content
        }
    }
}

@available(iOS 16.0, *)
private struct TightTextWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let full = text.sizeThatFits(proposal)
        guard let width = proposal.width, width.isFinite, width > 0,
              full.width >= width - 0.5 else { return full }
        // Самая узкая ширина с тем же числом строк (высота монотонна по ширине).
        var narrow: CGFloat = 0
        var wide = width
        while wide - narrow > 0.5 {
            let mid = (narrow + wide) / 2
            let height = text.sizeThatFits(ProposedViewSize(width: mid, height: nil)).height
            if height > full.height + 0.5 { narrow = mid } else { wide = mid }
        }
        return CGSize(width: min(width, ceil(wide)), height: full.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
