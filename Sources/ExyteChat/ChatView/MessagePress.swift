//
//  MessagePress.swift
//  Chat
//

import SwiftUI

/// Долгое нажатие на сообщение: пузырь «вдавливается» перед меню (Telegram;
/// `MESSAGE_ANIMATIONS_SPEC.md`, A19). Только поведение и числа — кода Telegram здесь нет.
///
/// Через `delay` после касания пузырь за `duration` линейно сжимается до
/// `scale(forBubbleWidth:)`; на конце — вибрация и меню, которое стартует со сжатого
/// пузыря и пружиной возвращает его к 1. Отпустили раньше, сдвинули палец дальше
/// `cancelDistance` или пошёл скролл — пузырь за `releaseDuration` разжимается.
enum MessagePress {
    /// Пауза до начала сжатия: короткий тап не должен «дёргать» пузырь.
    static let delay: TimeInterval = 0.12
    /// Само сжатие (линейно). Меню — через `delay + duration` ≈ 0.32 с.
    static let duration: TimeInterval = 0.2
    /// Возврат при отмене (easeOut).
    static let releaseDuration: TimeInterval = 0.2
    /// Сдвиг пальца, после которого нажатие отменяется.
    static let cancelDistance: CGFloat = 12
    /// Касание у левого края — системный свайп «назад», не нажатие на пузырь.
    static let leftEdgeInset: CGFloat = 8

    /// По ширине пузырь теряет 15 pt, но не больше 30% (широкий ≈ 0.95, узкий сильнее).
    /// При «Уменьшении движения» амплитуда вдвое меньше.
    static func scale(forBubbleWidth width: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard width > 0 else { return 1 }
        let full = max(0.7, (width - 15) / width)
        return reduceMotion ? 1 - (1 - full) * 0.5 : full
    }
}

/// Какая строка ленты сейчас нажата и насколько (0 — покой, 1 — сжата).
/// Один на ленту; ячейки смотрят на него через `MessagePressHost`.
@MainActor
final class MessagePressTracker: ObservableObject {
    @Published private(set) var pressedId: String?
    @Published private(set) var progress: CGFloat = 0

    func press(_ id: String) {
        pressedId = id
        withAnimation(.linear(duration: MessagePress.duration)) {
            progress = 1
        }
    }

    /// Возврат к покою; `animation == nil` — мгновенно.
    func release(_ animation: Animation? = .easeOut(duration: MessagePress.releaseDuration)) {
        guard pressedId != nil else { return }
        if let animation {
            withAnimation(animation) { progress = 0 }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { progress = 0 }
        }
    }
}

private struct MessagePressProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Прогресс «вдавливания» пузыря этой строки (0…1).
    var messagePressProgress: CGFloat {
        get { self[MessagePressProgressKey.self] }
        set { self[MessagePressProgressKey.self] = newValue }
    }
}

/// Обёртка содержимого ячейки: отдаёт прогресс нажатия только своей строке —
/// остальные ячейки получают 0 и не перерисовываются.
struct MessagePressHost<Content: View>: View {
    @ObservedObject var tracker: MessagePressTracker
    let id: String
    let content: Content

    var body: some View {
        content.environment(\.messagePressProgress, tracker.pressedId == id ? tracker.progress : 0)
    }
}

/// Сжатие пузыря вокруг его центра на `progress` (масштаб зависит от ширины).
struct MessagePressShrink: ViewModifier {
    @Environment(\.messagePressProgress) private var progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        let target = MessagePress.scale(forBubbleWidth: width, reduceMotion: reduceMotion)
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { width = $0 }
                }
            )
            .scaleEffect(1 - (1 - target) * progress)
    }
}
