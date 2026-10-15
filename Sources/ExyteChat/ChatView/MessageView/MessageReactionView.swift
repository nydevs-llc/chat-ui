//
//  MessageView+Reaction.swift
//  Chat
//

import SwiftUI

extension MessageView {
    
    @ViewBuilder
    func reactionsView(_ message: Message, maxReactions: Int = 4) -> some View {
        // If text has a single character, cap at 3; otherwise keep provided max
        let adjustedMaxReactions = (message.text.count <= 2) ? 3 : maxReactions

        let prepared = prepareReactions(message: message, maxReactions: adjustedMaxReactions)
        // "+N" equals hidden count: total - visibleCount
        let visibleCount = prepared.reactions.count
        let hiddenCount = max(0, message.reactions.count - visibleCount)
        let overflowText = message.user.isCurrentUser ? " +\(hiddenCount)" : "+\(hiddenCount) "

        HStack(spacing: -bubbleSize.width / 4) {
            if !message.user.isCurrentUser {
                overflowBubbleView(
                    leadingSpacer: true,
                    needsOverflowBubble: prepared.needsOverflowBubble,
                    text: overflowText,
                    containsReactionFromCurrentUser: prepared.overflowContainsCurrentUser
                )
            }

            ForEach(Array(prepared.reactions.enumerated()), id: \.element) { index, reaction in
                ReactionBubble(reaction: reaction, font: Font(font))
                    .transition(.scaleAndFade)
                    .zIndex(message.user.isCurrentUser ? Double(prepared.reactions.count - index)
                                                      : Double(index + 1))
                    .sizeGetter($bubbleSize)
            }

            if message.user.isCurrentUser {
                overflowBubbleView(
                    leadingSpacer: false,
                    needsOverflowBubble: prepared.needsOverflowBubble,
                    text: overflowText,
                    containsReactionFromCurrentUser: prepared.overflowContainsCurrentUser
                )
            }
        }
        .offset(x: message.user.isCurrentUser ? -(bubbleSize.height / 2) : (bubbleSize.height / 2), y: 0)
    }
    
    @ViewBuilder
    func overflowBubbleView(leadingSpacer:Bool, needsOverflowBubble:Bool, text:String, containsReactionFromCurrentUser:Bool) -> some View {
        if needsOverflowBubble {
            ReactionBubble(
                reaction: .init(
                    user: .init(
                        id: "null",
                        name: "",
                        avatarURL: nil, avatarCachedImage: nil,
                        isCurrentUser: containsReactionFromCurrentUser
                    ),
                    type: .emoji(text),
                    status: .sent
                ),
                font: .footnote.weight(.light)
            )
            .padding(message.user.isCurrentUser ? .trailing : .leading, -3)
        }
    }
    
    struct PreparedReactions {
        /// Sorted Reactions by most recent -> oldest (trimmed to maxReactions)
        let reactions:[Reaction]
        /// Indicates whether we need to add an overflow bubble (due to the number of Reactions exceeding maxReactions)
        let needsOverflowBubble:Bool
        /// Indicates whether the clipped reactions (oldest reactions beyond maxReaction) contain a reaction from the current user
        /// - Note: This value is used to color the background of the overflow bubble
        let overflowContainsCurrentUser:Bool
    }
    
    // MARK: - prepareReactions: (my reaction always first)
    private func prepareReactions(message: Message, maxReactions: Int) -> PreparedReactions {
        guard maxReactions > 1, !message.reactions.isEmpty else {
            return .init(reactions: [], needsOverflowBubble: false, overflowContainsCurrentUser: false)
        }

        // 1) Split: mine vs others
        //    Then sort each bucket by createdAt desc and concatenate: mine first, then others.
        //    This guarantees: my reaction is always first if it exists.
        let mine   = message.reactions.filter { $0.user.isCurrentUser }
            .sorted(by: { $0.createdAt > $1.createdAt })
        let others = message.reactions.filter { !$0.user.isCurrentUser }
            .sorted(by: { $0.createdAt > $1.createdAt })

        var ordered = mine + others

        // 2) Overflow logic
        let needsOverflowBubble = ordered.count > maxReactions
        // Visible bubbles count (excluding the "+N" bubble) when overflow is present
        let visibleSlots = needsOverflowBubble ? (maxReactions - 1) : maxReactions

        // Hidden tail AFTER taking visible
        let hiddenTail = ordered.count > visibleSlots ? Array(ordered.dropFirst(visibleSlots)) : []
        let overflowContainsCurrentUser = hiddenTail.contains(where: { $0.user.isCurrentUser })

        // Trim to visible portion
        if ordered.count > visibleSlots {
            ordered = Array(ordered.prefix(visibleSlots))
        }

        // 3) Layout direction:
        //    keep your old reversal rule for opponent messages (z-index/overlap expectation)
        let layoutOrdered = message.user.isCurrentUser ? ordered : ordered.reversed()

        return .init(
            reactions: layoutOrdered,
            needsOverflowBubble: needsOverflowBubble,
            overflowContainsCurrentUser: overflowContainsCurrentUser
        )
    }
}

struct ReactionBubble: View {
    
    @Environment(\.chatTheme) var theme
    
    let reaction: Reaction
    let font: Font
    
    @State private var phase = 0.0
    private var isOverflowText: Bool {
           (reaction.emoji ?? "").hasPrefix("+")
       }

    private var fillColor: Color {
        // Special case for "+N" overflow bubble
        if isOverflowText {
            // If hidden set contains my reaction, use myMessage; otherwise friendMessage
            return theme.colors.friendMessage
        }

        // Regular bubbles
        switch reaction.status {
        case .error:
            return .red
        case .sending, .sent, .read:
            return reaction.user.isCurrentUser ? theme.colors.myMessage : theme.colors.friendMessage
        }
    }
    
    private var textColor: Color {
            // For overflow "+N" ensure contrast with background
//            if isOverflowText {
//                return .dolyaBlue
//            }
            // For normal emoji keep system coloring (don’t tint)
        return .dolyaBlue //.primary
        }
    
    var opacity: Double {
        switch reaction.status {
        case .sent, .read:
            return 1.0
        case .sending, .error:
            return 0.7
        }
    }
    
    var body: some View {
        Text(reaction.emoji ?? "?")
            .font(font)
            .opacity(opacity)
            .foregroundStyle(textColor)
            .padding(6)
            .background(
                ZStack {
                    Circle()
                        .fill(fillColor)
                    // If the reaction is in flight, animate the stroke
                    if reaction.status == .sending {
                        Circle()
                            .stroke(style: .init(lineWidth: 2, lineCap: .round, dash: [100, 50], dashPhase: phase))
                            .fill(theme.colors.friendMessage)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                    phase -= 150
                                }
                            }
                    // Otherwise just stroke the circle normally
                    } else {
                        Circle()
                            .stroke(style: .init(lineWidth: 2))
                            .fill(theme.colors.mainBackground)
                    }
                }
            )
    }
}

// MARK: - Telegram-style reaction chips

/// Обработчик тапа по чипу реакции. Кладётся в окружение каждой ячейки ленты
/// (`SonataUIList`): ячейка — новый корень SwiftUI и окружение `ChatView` не наследует.
private struct MessageReactionTapKey: EnvironmentKey {
    static let defaultValue: ((Message, String) -> Void)? = nil
}

extension EnvironmentValues {
    var messageReactionTap: ((Message, String) -> Void)? {
        get { self[MessageReactionTapKey.self] }
        set { self[MessageReactionTapKey.self] = newValue }
    }
}

/// Чипы реакций, сгруппированные по эмоджи (Telegram). Внутри чипа — эмоджи и аватарки
/// поставивших (пока реакций на сообщении не больше трёх и аватарки известны), иначе
/// счётчик. Чип со своей реакцией залит акцентом. Тап переключает свою реакцию этим эмоджи.
/// Порядок — порядок первых появлений в `message.reactions` (сервер отдаёт по времени).
struct ReactionChipsRow: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.messageReactionTap) private var onTap

    let message: Message
    /// На исходящем пузыре (заливка цветом бренда) акцент — белый.
    let isOutgoingBubble: Bool

    struct Chip: Identifiable, Equatable {
        let emoji: String
        let users: [User]
        let isMine: Bool
        let isPending: Bool
        var count: Int { users.count }
        var id: String { emoji }
    }

    static func chips(for reactions: [Reaction]) -> [Chip] {
        var order: [String] = []
        var grouped: [String: [Reaction]] = [:]
        for reaction in reactions {
            guard let emoji = reaction.emoji else { continue }
            if grouped[emoji] == nil { order.append(emoji) }
            grouped[emoji, default: []].append(reaction)
        }
        return order.map { emoji in
            let group = grouped[emoji] ?? []
            let mine = group.first { $0.user.isCurrentUser }
            var pending = false
            if let mine, case .sending = mine.status { pending = true }
            return Chip(emoji: emoji, users: group.map(\.user), isMine: mine != nil, isPending: pending)
        }
    }

    private var chips: [Chip] { Self.chips(for: message.reactions) }

    /// Telegram показывает лица, пока реакций мало; дальше — числа.
    private var showsAvatars: Bool {
        message.reactions.count <= 3
            && message.reactions.allSatisfy { $0.user.avatarURL != nil || $0.user.avatarCachedImage != nil }
    }

    private var accent: Color { isOutgoingBubble ? .white : theme.colors.myMessage }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips) { chip in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTap?(message, chip.emoji)
                } label: {
                    chipLabel(chip)
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(.interpolatingSpring(stiffness: 900, damping: 60), value: chips)
    }

    private func chipLabel(_ chip: Chip) -> some View {
        HStack(spacing: 4) {
            Text(chip.emoji)
                .font(.system(size: 16))
            if showsAvatars {
                HStack(spacing: -6) {
                    ForEach(Array(chip.users.prefix(2).enumerated()), id: \.offset) { _, user in
                        AvatarView(url: user.avatarURL, cachedImage: user.avatarCachedImage, avatarSize: 22)
                            .overlay(Circle().strokeBorder(chipFill(chip), lineWidth: 1.5))
                    }
                }
            } else if chip.count > 1 || !chip.isMine {
                Text("\(chip.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(countColor(chip))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, showsAvatars ? 3 : 8)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(chipFill(chip)))
        .opacity(chip.isPending ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.emoji) \(chip.count)")
        .accessibilityAddTraits(chip.isMine ? [.isButton, .isSelected] : .isButton)
    }

    private func chipFill(_ chip: Chip) -> Color {
        chip.isMine ? accent : accent.opacity(isOutgoingBubble ? 0.22 : 0.14)
    }

    private func countColor(_ chip: Chip) -> Color {
        if chip.isMine { return isOutgoingBubble ? theme.colors.myMessage : .white }
        return isOutgoingBubble ? .white : accent
    }
}
