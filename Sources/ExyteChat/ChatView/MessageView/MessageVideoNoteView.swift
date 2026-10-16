//
//  MessageVideoNoteView.swift
//  Chat
//
//  Кружок в ленте: без пузыря, капсула времени со статусом в правом нижнем
//  углу описанного квадрата (у входящих и у исходящих, как в Telegram),
//  реакции под кругом, цитата ответа над ним (прячется, пока кружок увеличен).
//

import SwiftUI

struct MessageVideoNoteView: View {
    @Environment(\.chatVideoNoteRendering) private var rendering
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let message: Message
    let note: MessageVideoNote
    let isDisplayingMessageMenu: Bool
    let showsTime: Bool
    let onRetry: () -> Void

    private var isOutgoing: Bool { message.user.isCurrentUser }

    private var diameter: CGFloat {
        if note.isEnlarged && !isDisplayingMessageMenu {
            return MessageVideoNote.enlargedDiameter(listWidth: UIScreen.main.bounds.width)
        }
        return MessageVideoNote.baseDiameter(isRegularWidth: sizeClass == .regular)
    }

    var body: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if let reply = message.replyMessage, !note.isEnlarged {
                NoBubbleReplyQuote(reply: reply, isOutgoing: isOutgoing)
            }

            circle
                .overlay(alignment: .bottomLeading) {
                    if showsTime { timeCapsule }
                }

            if note.isRemoved, let caption = rendering?.removedCaption(isOutgoing), !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isOutgoing ? Color(red: 1, green: 0.3, blue: 0.3) : Color.secondary)
                    .frame(maxWidth: diameter, alignment: isOutgoing ? .trailing : .leading)
            }

            if !isDisplayingMessageMenu, !message.reactions.isEmpty, !message.isDeleted, !note.isEnlarged {
                ReactionChipsRow(message: message, isOutgoingBubble: false)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .onAppear { rendering?.onVisibilityChange(message, true) }
        .onDisappear { rendering?.onVisibilityChange(message, false) }
    }

    @ViewBuilder
    private var circle: some View {
        Group {
            if let rendering {
                rendering.content(message, note, diameter)
            } else {
                placeholder
            }
        }
        .frame(width: diameter, height: diameter)
        // Кругом режет само приложение (только видео/постер): кольцо, ручка сека
        // и капсула длительности лежат поверх и не обрезаются.
        .contentShape(Circle())
        // Увеличение до min(404, ширина − 20) — пружиной за 0.3 с; при
        // «Уменьшении движения» — плавная смена без пружины (§8.3, §17).
        .animation(
            reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.3, dampingFraction: 0.8),
            value: note.isEnlarged
        )
        // В копии под меню — только картинка: тап закрывает меню, а не играет.
        .allowsHitTesting(!isDisplayingMessageMenu)
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.35))
            .overlay(alignment: .bottomLeading) {
                Text(MessageVideoNote.formatDuration(seconds: note.durationMs / 1000))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
                    .fixedSize()
                    // Правый край на mid − 55, низ = низ кружка (вне диска).
                    .frame(width: max(0, diameter / 2 - 55), alignment: .trailing)
            }
    }

    /// Капсула времени со статусом: левый край на mid + 55 (+25 у увеличенного),
    /// низ = низ кружка; у исходящего, прижатого вправо, не выходит за край
    /// квадрата больше чем на 4 (Telegram клипует к ширине ленты − 4).
    private var timeCapsule: some View {
        let leadingEdge = diameter / 2 + 55 + (note.isEnlarged ? 25 : 0)
        // Полоса [0, limit]: капсула стоит на leadingEdge, а если не влезает до
        // limit — прижимается к нему правым краем (min(leadingEdge, limit − w)).
        let limit = isOutgoing ? diameter + 4 : leadingEdge + 200
        return NoBubbleTimeCapsule(message: message, onRetry: onRetry)
            .fixedSize()
            .frame(minWidth: limit - leadingEdge, alignment: .leading)
            .frame(width: limit, alignment: .trailing)
    }
}

extension MessageView {
    /// Кружок рисуется своей композицией, пока он не удалён у получателя
    /// модерацией (там — заглушка той же композиции) и не удалено само сообщение.
    static func videoNote(of message: Message) -> MessageVideoNote? {
        guard !message.isDeleted else { return nil }
        return message.videoNote
    }
}
