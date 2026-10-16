//
//  StickerRendering.swift
//  Chat
//
//  Стикеры и большие эмодзи в ленте (по мотивам Telegram).
//
//  Конфигурация — значение, как и у реакций (`MessageReactionsConfiguration`):
//  приложение отдаёт вью-билдеры (Lottie, кеш файлов) и обработчики тапов,
//  форк отвечает только за раскладку без пузыря.
//

import SwiftUI

/// Где в ленте рисуется анимация — чтобы приложение могло помнить, что она уже
/// проигрывалась в этой сессии чата, и не повторять её при переиспользовании
/// ячейки или смене статуса «доставлено/прочитано» (Telegram: `alreadyPlayedStickers`).
public struct StickerPlaybackContext: Hashable, Sendable {
    /// `Message.id` — у черновика и доставленного сообщения он один и тот же (guid).
    public let messageId: String
    /// Номер эмодзи в «большом» сообщении (0…2); у стикера всегда 0.
    public let index: Int
    /// Растёт на каждом тапе — анимация обязана проиграться заново.
    public let replayToken: Int

    public init(messageId: String, index: Int = 0, replayToken: Int = 0) {
        self.messageId = messageId
        self.index = index
        self.replayToken = replayToken
    }

    /// Ключ «уже проигрывалось» без учёта тапов.
    public var playKey: String { "\(messageId)#\(index)" }
}

public struct ChatStickerRendering {
    /// Содержимое стикера (анимация / картинка) в заданном размере.
    public var stickerContent: (MessageSticker, CGSize, StickerPlaybackContext) -> AnyView
    /// Анимированный большой эмодзи. `nil` — анимации для эмодзи нет, форк рисует
    /// статичный глиф того же размера.
    public var animatedEmojiContent: (String, CGFloat, StickerPlaybackContext) -> AnyView?
    /// Тап по стикеру в ленте (приложение открывает шторку пака).
    public var onStickerTap: (Message) -> Void
    /// Тап по большому эмодзи (повтор анимации, хаптик и аналитика — у приложения).
    public var onBigEmojiTap: (Message, String) -> Void
    /// Рисовать ли сообщения из 1–3 эмодзи крупно, без пузыря.
    public var bigEmojiEnabled: Bool

    public init(
        stickerContent: @escaping (MessageSticker, CGSize, StickerPlaybackContext) -> AnyView,
        animatedEmojiContent: @escaping (String, CGFloat, StickerPlaybackContext) -> AnyView? = { _, _, _ in nil },
        onStickerTap: @escaping (Message) -> Void = { _ in },
        onBigEmojiTap: @escaping (Message, String) -> Void = { _, _ in },
        bigEmojiEnabled: Bool = true
    ) {
        self.stickerContent = stickerContent
        self.animatedEmojiContent = animatedEmojiContent
        self.onStickerTap = onStickerTap
        self.onBigEmojiTap = onBigEmojiTap
        self.bigEmojiEnabled = bigEmojiEnabled
    }
}

private struct ChatStickerRenderingKey: EnvironmentKey {
    static let defaultValue: ChatStickerRendering? = nil
}

extension EnvironmentValues {
    /// Ячейки ленты — отдельные корни SwiftUI (`UIHostingConfiguration`), поэтому
    /// значение кладётся в окружение каждой ячейки явно (см. `SonataUIList`).
    var chatStickerRendering: ChatStickerRendering? {
        get { self[ChatStickerRenderingKey.self] }
        set { self[ChatStickerRenderingKey.self] = newValue }
    }
}

// MARK: - Big emoji

/// Сообщение из 1–3 эмодзи (и ничего больше, кроме пробелов по краям) рисуется
/// крупно без пузыря: 1 — 94 pt, 2 — 79, 3 — 65 (как в Telegram: 94 × 1.0 / 0.84 / 0.69).
public enum BigEmoji {
    public static let maxCount = 3

    /// Эмодзи сообщения, если оно «большое», иначе `nil`.
    public static func emojis(in text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var result: [String] = []
        for character in trimmed {
            guard isEmoji(character) else { return nil }
            result.append(String(character))
            if result.count > maxCount { return nil }
        }
        return result
    }

    /// Ровно один эмодзи после обрезки пробелов — триггер подсказок стикеров.
    public static func singleEmoji(in text: String) -> String? {
        guard let list = emojis(in: text), list.count == 1 else { return nil }
        return list[0]
    }

    public static func pointSize(forCount count: Int) -> CGFloat {
        switch count {
        case 1: return 94
        case 2: return 79
        default: return 65
        }
    }

    /// Графема — эмодзи: либо эмодзи по умолчанию (😀, 🇷🇺), либо текстовый символ,
    /// превращённый в эмодзи последовательностью (☺️ с VS16, #️⃣, ZWJ-склейки).
    /// Одиночные цифры, `#`, `©` без VS16 — текст.
    public static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        guard first.properties.isEmoji, scalars.count > 1 else { return false }
        return scalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 || $0.value == 0x200D }
    }
}
