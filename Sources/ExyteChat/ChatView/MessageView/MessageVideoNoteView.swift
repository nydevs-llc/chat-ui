//
//  MessageVideoNoteView.swift
//  Chat
//
//  Кружок в ленте: без пузыря, капсула времени со статусом сбоку внизу
//  (у исходящего — слева, у входящего — справа), реакции под кругом,
//  цитата ответа над ним (прячется, пока кружок увеличен).
//

import SwiftUI

struct MessageVideoNoteView: View {
    @Environment(\.chatVideoNoteRendering) private var rendering
    @Environment(\.horizontalSizeClass) private var sizeClass

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

            HStack(alignment: .bottom, spacing: 4) {
                if isOutgoing, showsTime, !note.isEnlarged { timeCapsule }
                circle
                if !isOutgoing, showsTime, !note.isEnlarged { timeCapsule }
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
        .clipShape(Circle())
        .contentShape(Circle())
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
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
                    .padding(.leading, diameter / 2 - 56)
                    .padding(.bottom, 18)
            }
    }

    private var timeCapsule: some View {
        NoBubbleTimeCapsule(message: message, onRetry: onRetry)
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
