//
//  MessageReactions.swift
//  Chat
//
//  Реакции на сообщения в стиле Telegram: одна реакция пользователя на сообщение,
//  тот же эмоджи снимает её, другой — заменяет.
//
//  Конфигурация — значение, а не объект-делегат: `ChatView` хранит её как обычное
//  поле, лента берёт свежую на каждом обновлении, а приложение отвечает одним
//  замыканием без собственного состояния.
//

import Foundation

/// Готовое намерение пользователя. Правило переключения уже применено библиотекой —
/// приложению остаётся превратить `.set` / `.remove` в запрос к серверу.
public struct MessageReactionEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Поставить или заменить свою реакцию.
        case set
        /// Снять свою реакцию (повторный выбор того же эмоджи).
        case remove
    }

    /// Откуда пришёл выбор — для аналитики.
    public enum Source: String, Equatable, Sendable {
        case quickBar = "quick_bar"
        case emojiGrid = "emoji_grid"
        case chip
    }

    public let messageId: String
    public let reaction: String
    public let kind: Kind
    public let source: Source

    public init(messageId: String, reaction: String, kind: Kind, source: Source) {
        self.messageId = messageId
        self.reaction = reaction
        self.kind = kind
        self.source = source
    }

    /// Единственное место правила «тот же эмоджи — снять, другой — поставить».
    public static func resolve(_ emoji: String, on message: Message, source: Source) -> MessageReactionEvent {
        let isMineAlready = message.reactions.contains { $0.user.isCurrentUser && $0.type == .emoji(emoji) }
        return MessageReactionEvent(
            messageId: message.id,
            reaction: emoji,
            kind: isMineAlready ? .remove : .set,
            source: source
        )
    }
}

public struct MessageReactionsConfiguration {
    /// Быстрый ряд в меню. По умолчанию — набор Telegram.
    public var quickReactions: [String]
    /// Можно ли реагировать на конкретное сообщение (меню без пилюли, чипы без тапа).
    public var canReact: (Message) -> Bool
    /// Стрелка раскрытия в полную сетку эмоджи.
    public var allowsEmojiGrid: Bool
    /// Строка «кто как отреагировал» сверху экрана меню (наследие exyte; у Telegram её нет).
    public var showsOverview: (Message) -> Bool
    /// VoiceOver-подписи стрелки. Библиотека строки не локализует — их передаёт приложение.
    public var expandAccessibilityLabel: String
    public var collapseAccessibilityLabel: String
    public var onEvent: (Message, MessageReactionEvent) -> Void

    /// Только для моста с `ReactionDelegate`: у делегата набор и сетка задаются на сообщение.
    var perMessageQuickReactions: ((Message) -> [String]?)?
    var perMessageAllowsEmojiGrid: ((Message) -> Bool)?

    public init(
        quickReactions: [String] = MessageReactionsConfiguration.telegramQuickReactions,
        canReact: @escaping (Message) -> Bool = { _ in true },
        allowsEmojiGrid: Bool = true,
        showsOverview: @escaping (Message) -> Bool = { _ in false },
        expandAccessibilityLabel: String = "More reactions",
        collapseAccessibilityLabel: String = "Close",
        onEvent: @escaping (Message, MessageReactionEvent) -> Void
    ) {
        self.quickReactions = quickReactions
        self.canReact = canReact
        self.allowsEmojiGrid = allowsEmojiGrid
        self.showsOverview = showsOverview
        self.expandAccessibilityLabel = expandAccessibilityLabel
        self.collapseAccessibilityLabel = collapseAccessibilityLabel
        self.onEvent = onEvent
    }

    public static let telegramQuickReactions = ["❤️", "👍", "👌", "🔥", "🥰", "👎", "👏"]
}

extension MessageReactionsConfiguration {
    /// Совместимость с API exyte (`reactionDelegate:` / `.messageReactionDelegate` /
    /// `.onMessageReaction`): делегат получает выбранный эмоджи как раньше, без `kind`.
    init(delegate: ReactionDelegate) {
        self.init(
            quickReactions: [],
            canReact: { delegate.canReact(to: $0) },
            allowsEmojiGrid: true,
            showsOverview: { delegate.shouldShowOverview(for: $0) },
            onEvent: { message, event in
                delegate.didReact(to: message, reaction: DraftReaction(messageID: message.id, type: .emoji(event.reaction)))
            }
        )
        perMessageQuickReactions = { delegate.reactions(for: $0)?.map(\.toString) }
        perMessageAllowsEmojiGrid = { delegate.allowEmojiSearch(for: $0) }
    }

    func quickReactions(for message: Message) -> [String] {
        let list = perMessageQuickReactions?(message) ?? quickReactions
        return list.isEmpty ? Self.telegramQuickReactions : list
    }

    func allowsEmojiGrid(for message: Message) -> Bool {
        perMessageAllowsEmojiGrid?(message) ?? allowsEmojiGrid
    }
}
