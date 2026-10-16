//
//  MessageFooter.swift
//  Chat
//
//  Подвал сообщения — произвольная строка ПОД пузырём (стикером, эмодзи,
//  карточкой), которую рисует приложение. Форк знает только «у сообщения есть
//  подвал с таким ключом» и где его поставить; что в нём — решает приложение
//  (например, чип «Неизвестно» у статуса прочтения под замком подписки).
//
//  Ключ входит в `Message.==`/`hash` намеренно: ячейка ленты переконфигурируется
//  только когда сообщение изменилось, и переезд подвала на новое сообщение
//  обязан перерисовать и старую строку (подвал уходит), и новую (появляется).
//

import SwiftUI

/// Метка подвала сообщения. `id` — непрозрачный для форка ключ содержимого:
/// поменялся ключ — строка перерисовывается.
public struct MessageFooter: Hashable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// Строит вью подвала для сообщения с непустым `Message.footer`.
public typealias MessageFooterBuilder = (Message, MessageFooter) -> AnyView

private struct ChatMessageFooterBuilderKey: EnvironmentKey {
    static let defaultValue: MessageFooterBuilder? = nil
}

extension EnvironmentValues {
    /// Ячейки ленты — отдельные корни SwiftUI (`UIHostingConfiguration`), поэтому
    /// значение кладётся в окружение каждой ячейки явно (см. `SonataUIList`).
    var chatMessageFooterBuilder: MessageFooterBuilder? {
        get { self[ChatMessageFooterBuilderKey.self] }
        set { self[ChatMessageFooterBuilderKey.self] = newValue }
    }
}
