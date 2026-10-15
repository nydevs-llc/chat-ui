//
//  MessageStickerView.swift
//  Chat
//
//  Сообщения без пузыря: стикер и «большие эмодзи» (1–3 эмодзи без текста).
//  Поведение по мотивам Telegram: стикер ≤ 160×160 pt, время со статусом — в
//  капсуле в правом нижнем углу, тап — повтор анимации (+ шторка пака у стикера).
//

import SwiftUI
import NukeUI

/// Время + статус в капсуле поверх стикера / большого эмодзи (пузыря нет —
/// подложка нужна, чтобы время читалось на любом фоне).
struct NoBubbleTimeCapsule: View {
    @Environment(\.chatTheme) private var theme

    let message: Message
    let onRetry: () -> Void

    var body: some View {
        CapsuleTimeContainer(isCurrentUser: message.user.isCurrentUser, theme: theme) {
            HStack(spacing: 2) {
                MessageTimeText(
                    text: message.time,
                    isCurrentUser: message.user.isCurrentUser,
                    theme: theme,
                    needsCapsule: true
                )
                if message.user.isCurrentUser, let status = message.status, !message.isDeleted {
                    MessageStatusView(
                        status: status,
                        needsCapsule: true,
                        colorSet: MessageStatusColorSet(
                            sending: .white.opacity(0.85),
                            sent: .white.opacity(0.85),
                            received: .white.opacity(0.85),
                            read: .white.opacity(0.85)
                        ),
                        onRetry: onRetry
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Цитата ответа над сообщением без пузыря — в маленькой собственной подложке.
struct NoBubbleReplyQuote: View {
    @Environment(\.chatTheme) private var theme
    let reply: ReplyMessage
    let isOutgoing: Bool

    var body: some View {
        ReplyQuoteView(reply: reply, isOutgoing: false)
            .padding(6)
            .frame(maxWidth: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.colors.friendMessage)
            )
    }
}

/// Стикер в ленте.
struct MessageStickerView: View {
    @Environment(\.chatStickerRendering) private var rendering

    let message: Message
    let sticker: MessageSticker
    let isDisplayingMessageMenu: Bool
    let showsTime: Bool
    let onRetry: () -> Void

    @State private var replayToken = 0

    var body: some View {
        let size = sticker.displaySize
        VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 4) {
            if let reply = message.replyMessage {
                NoBubbleReplyQuote(reply: reply, isOutgoing: message.user.isCurrentUser)
            }

            content(size: size)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    replayToken += 1
                    rendering?.onStickerTap(message)
                }
                // В копии под меню тап закрывает меню, а не открывает шторку пака.
                .allowsHitTesting(!isDisplayingMessageMenu)
                .overlay(alignment: .bottomTrailing) {
                    if showsTime {
                        NoBubbleTimeCapsule(message: message, onRetry: onRetry)
                            .offset(x: 2, y: 2)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(sticker.emoji))
                .accessibilityAddTraits(.isImage)

            if !isDisplayingMessageMenu, !message.reactions.isEmpty, !message.isDeleted {
                ReactionChipsRow(message: message, isOutgoingBubble: false)
            }
        }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let rendering {
            rendering.stickerContent(sticker, size, replayToken)
        } else if let url = sticker.thumbnailURL ?? (sticker.isAnimated ? nil : sticker.fileURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    Text(sticker.emoji).font(.system(size: size.height * 0.6))
                }
            }
        } else {
            Text(sticker.emoji).font(.system(size: size.height * 0.6))
        }
    }
}

/// Сообщение из 1–3 эмодзи: крупно и без пузыря.
struct BigEmojiMessageView: View {
    @Environment(\.chatStickerRendering) private var rendering

    let message: Message
    let emojis: [String]
    let isDisplayingMessageMenu: Bool
    let showsTime: Bool
    let onRetry: () -> Void

    @State private var replayTokens: [Int: Int] = [:]

    var body: some View {
        let side = BigEmoji.pointSize(forCount: emojis.count)
        VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 4) {
            if let reply = message.replyMessage {
                NoBubbleReplyQuote(reply: reply, isOutgoing: message.user.isCurrentUser)
            }

            HStack(spacing: 0) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                    glyph(emoji, side: side, token: replayTokens[index] ?? 0)
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            replayTokens[index, default: 0] += 1
                            rendering?.onBigEmojiTap(message, emoji)
                        }
                }
            }
            .allowsHitTesting(!isDisplayingMessageMenu)
            .padding(.bottom, showsTime ? 14 : 0)
            .overlay(alignment: .bottomTrailing) {
                if showsTime {
                    NoBubbleTimeCapsule(message: message, onRetry: onRetry)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(emojis.joined()))

            if !isDisplayingMessageMenu, !message.reactions.isEmpty, !message.isDeleted {
                ReactionChipsRow(message: message, isOutgoingBubble: false)
            }
        }
    }

    @ViewBuilder
    private func glyph(_ emoji: String, side: CGFloat, token: Int) -> some View {
        if let animated = rendering?.animatedEmojiContent(emoji, side, token) {
            animated
        } else {
            // Глиф системного шрифта визуально меньше своего кегля — 0.8 стороны
            // даёт ту же оптическую величину, что и Lottie во всю сторону.
            Text(emoji)
                .font(.system(size: side * 0.8))
                .fixedSize()
        }
    }
}

extension MessageView {
    /// Эмодзи «большого» сообщения или `nil`. Только по явному согласию приложения
    /// (`ChatStickerRendering.bigEmojiEnabled`): у сторонних потребителей форка
    /// раскладка не меняется.
    static func bigEmojis(of message: Message, rendering: ChatStickerRendering?) -> [String]? {
        guard rendering?.bigEmojiEnabled == true,
              message.type == .text,
              !message.isDeleted,
              !message.isStreaming,
              message.attachments.isEmpty,
              message.recording == nil,
              message.publicationAttachment == nil,
              message.sticker == nil else { return nil }
        return BigEmoji.emojis(in: message.text)
    }
}
