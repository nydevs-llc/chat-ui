//
//  MessageMenu+ContextMenuStyle.swift
//  Chat
//
//  Визуал контекстного меню сообщения по образцу Telegram-iOS:
//  размытый и затемнённый фон, «пилюля» реакций с хвостиком из двух кружков
//  над пузырём и скруглённый список действий под ним.
//
//  Числа взяты из исходников Telegram-iOS (коммит f1dd7a2d, 07.10.2026):
//  ReactionContextNode / ReactionContextBackgroundNode (пилюля и хвост),
//  ContextControllerExtractedPresentationNode (отступы и пружины),
//  DefaultDay/DarkPresentationTheme.contextMenu (цвета затемнения и подложки).
//

import SwiftUI
import UIKit

enum ContextMenuStyle {
    /// Пружина появления меню и пилюли: Telegram `animateSpring(duration: 0.42, damping: 104)`
    /// при жёсткости 900 — передемпфированная, без перелёта, оседает за ~0.4 с.
    static let appearSpring = Animation.interpolatingSpring(mass: 1, stiffness: 900, damping: 104)
    /// «Выпрыгивание» эмоджи: Telegram `scale 0.25 → 1, damping 60` — критическое демпфирование.
    static let itemPopSpring = Animation.interpolatingSpring(mass: 1, stiffness: 900, damping: 60)
    /// Закрытие: Telegram 0.2 с, `easeInEaseOut`.
    static let dismissAnimation = Animation.easeInOut(duration: 0.2)
    /// Фон: Telegram проявляет и гасит затемнение за 0.2 с.
    static let backdropAnimation = Animation.easeOut(duration: 0.2)

    // MARK: Пилюля реакций
    static let pillHeight: CGFloat = 46
    static let pillItemSize: CGFloat = 36
    static let pillItemSpacing: CGFloat = 8
    static let pillSideInset: CGFloat = 6
    /// Отступ пилюли от края экрана (Telegram: 11 + safe area).
    static let pillScreenInset: CGFloat = 11
    /// Насколько пилюля выступает за край пузыря со стороны хвоста (Telegram `backgroundOffset.x = 22`).
    static let pillAnchorOverhang: CGFloat = 22
    /// Минимальное расстояние от центра хвоста до края пилюли (Telegram: 23).
    static let pillTailEdgeInset: CGFloat = 23
    static let tailLargeCircle: CGFloat = 16
    static let tailSmallCircle: CGFloat = 8
    /// Зазор между пилюлей и пузырём: в него свешивается хвост.
    static let pillBubbleGap: CGFloat = 10
    /// Сколько эмоджи помещается в строку до кнопки раскрытия (Telegram: 8 слотов, последний — стрелка).
    static let maxVisibleEmojis = 7

    // MARK: Список действий
    static let actionsMinWidth: CGFloat = 220
    static let actionsMaxWidth: CGFloat = 260
    static let actionsCornerRadius: CGFloat = 24
    static let actionsVerticalInset: CGFloat = 8
    static let actionRowHeight: CGFloat = 44
    static let actionSideInset: CGFloat = 18
    static let actionIconSize: CGFloat = 24
    static let actionIconTitleSpacing: CGFloat = 14
    /// Зазор между пузырём и списком (Telegram `contentActionsSpacing = 7`).
    static let actionsBubbleGap: CGFloat = 7
    /// Отступ списка от края экрана (Telegram `actionsEdgeInset = 12`).
    static let actionsScreenInset: CGFloat = 12

    // MARK: Цвета
    /// Затемнение поверх блюра: день `#000a26` × 0.2, ночь чёрный × 0.6.
    static let dimColor = dynamicColor(
        light: UIColor(red: 0, green: 0.039, blue: 0.149, alpha: 0.2),
        dark: UIColor(white: 0, alpha: 0.6)
    )
    /// Подложка пилюли и меню без Liquid Glass: день `#f9f9f9` × 0.78, ночь `#252525` × 0.78.
    static let surfaceTint = dynamicColor(
        light: UIColor(white: 0.976, alpha: 0.78),
        dark: UIColor(white: 0.145, alpha: 0.78)
    )
    static let separatorColor = dynamicColor(
        light: UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.2),
        dark: UIColor(white: 1, alpha: 0.15)
    )
    static let highlightColor = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.1)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - Фон

/// Блюр содержимого чата и затемнение поверх.
struct ContextMenuBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(ContextMenuStyle.dimColor)
        }
    }
}

// MARK: - Подложка пилюли и меню

/// На iOS 26 — Liquid Glass, как у Telegram на iOS 26; ниже — материал с тоном подложки Telegram.
struct ContextMenuSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            materialSurface(content)
        }
        #else
        materialSurface(content)
        #endif
    }

    private func materialSurface(_ content: Content) -> some View {
        content.background(
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(ContextMenuStyle.surfaceTint)
            }
        )
    }
}

extension View {
    func contextMenuSurface<S: Shape>(_ shape: S) -> some View {
        modifier(ContextMenuSurface(shape: shape))
    }
}

// MARK: - Геометрия пилюли

/// Раскладка пилюли по горизонтали в координатах экрана.
///
/// Telegram цепляет пилюлю к краю пузыря со стороны хвоста: у входящего — к правому
/// краю (`maxX + 22`), у исходящего — к левому (`minX - 22`), затем прижимает к экрану.
/// Хвост стоит над тем же краем пузыря, но не ближе 23 pt к скруглению пилюли.
struct ReactionPillLayout: Equatable {
    let width: CGFloat
    let minX: CGFloat
    /// Центр большого кружка хвоста в координатах пилюли.
    let tailX: CGFloat
    /// Маленький кружок уходит наружу от пузыря: у входящего — вправо, у исходящего — влево.
    let tailPointsTrailing: Bool
    let itemSize: CGFloat
    /// Слотов в быстром ряду (эмоджи + стрелка) — столько же колонок у раскрытой сетки.
    let slotCount: Int

    init(anchor: CGRect, isIncoming: Bool, slotCount: Int, screenWidth: CGFloat) {
        let style = ContextMenuStyle.self
        self.slotCount = max(slotCount, 1)
        let slots = CGFloat(self.slotCount)
        let available = screenWidth - style.pillScreenInset * 2
        let natural = style.pillSideInset * 2 + slots * style.pillItemSize + (slots - 1) * style.pillItemSpacing
        // На узком экране Telegram ужимает ячейку, а не прячет слоты.
        itemSize = natural <= available
            ? style.pillItemSize
            : floor((available - style.pillSideInset * 2 - (slots - 1) * style.pillItemSpacing) / slots)
        width = min(natural, available)

        let anchorX = isIncoming ? anchor.maxX : anchor.minX
        let preferredMinX = isIncoming
            ? anchorX + style.pillAnchorOverhang - width
            : anchorX - style.pillAnchorOverhang
        minX = min(max(preferredMinX, style.pillScreenInset), screenWidth - style.pillScreenInset - width)

        let localAnchor = anchorX - minX
        tailX = min(max(localAnchor, style.pillTailEdgeInset), width - style.pillTailEdgeInset)
        tailPointsTrailing = isIncoming
    }
}

/// Капсула пилюли плюс два кружка хвоста — одним контуром, чтобы блюр/стекло
/// рисовались единой фигурой без швов. Пересечения сливаются по правилу nonzero.
struct ReactionPillShape: Shape {
    var tailX: CGFloat
    var tailPointsTrailing: Bool
    var showsTail: Bool = true

    func path(in rect: CGRect) -> Path {
        // Высота — реальная: раскрытая сетка растягивает ту же подложку вниз.
        let pillRect = rect
        var path = Path(roundedRect: pillRect, cornerRadius: ContextMenuStyle.pillHeight / 2, style: .continuous)
        guard showsTail else { return path }

        let large = ContextMenuStyle.tailLargeCircle
        let small = ContextMenuStyle.tailSmallCircle
        let largeRect = CGRect(x: rect.minX + tailX - large / 2, y: pillRect.maxY - large / 2, width: large, height: large)
        path.addEllipse(in: largeRect)

        let smallX = tailPointsTrailing ? largeRect.maxX - 3 : largeRect.minX + 3 - small
        path.addEllipse(in: CGRect(x: smallX, y: largeRect.maxY + 2, width: small, height: small))
        return path
    }
}

// MARK: - Пилюля реакций

/// Быстрый ряд реакций; по стрелке раскрывается в полную сетку эмоджи (как у Telegram:
/// `ReactionContextNode.expand()` — пилюля вырастает вниз поверх пузыря, хвост гаснет,
/// меню действий прячется). Раскрытие — состояние меню, а не пилюли: от него зависит
/// раскладка всего экрана, поэтому `isExpanded` приходит снаружи.
struct ReactionPillView: View {
    let emojis: [String]
    let selectedEmojis: [String]
    let layout: ReactionPillLayout
    let selectedColor: Color
    let allowsExpand: Bool
    let isExpanded: Bool
    let expandedHeight: CGFloat
    let expandAccessibilityLabel: String
    let collapseAccessibilityLabel: String
    let onExpandedChange: (Bool) -> Void
    let onPick: (String, MessageReactionEvent.Source) -> Void

    @State private var itemsAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            quickRow
            if isExpanded {
                EmojiGridPanel(
                    columns: layout.slotCount,
                    itemSize: layout.itemSize,
                    selectedEmojis: selectedEmojis,
                    selectedColor: selectedColor,
                    onPick: { pick($0, source: .emojiGrid) }
                )
                .transition(.opacity)
            }
        }
        .frame(width: layout.width, height: isExpanded ? expandedHeight : ContextMenuStyle.pillHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: ContextMenuStyle.pillHeight / 2, style: .continuous))
        .contextMenuSurface(
            ReactionPillShape(tailX: layout.tailX, tailPointsTrailing: layout.tailPointsTrailing, showsTail: !isExpanded)
        )
        .onAppear { itemsAppeared = true }
    }

    private var quickRow: some View {
        HStack(spacing: ContextMenuStyle.pillItemSpacing) {
            ForEach(Array(emojis.enumerated()), id: \.element) { index, emoji in
                Button {
                    pick(emoji, source: .quickBar)
                } label: {
                    emojiCell(emoji)
                }
                .buttonStyle(ReactionItemButtonStyle())
                .scaleEffect(itemsAppeared ? 1 : 0.25)
                .opacity(itemsAppeared ? 1 : 0)
                .animation(ContextMenuStyle.itemPopSpring.delay(0.08 + Double(index) * 0.035), value: itemsAppeared)
            }

            if allowsExpand {
                expandButton
                    .scaleEffect(itemsAppeared ? 1 : 0.01)
                    .animation(ContextMenuStyle.appearSpring.delay(0.12), value: itemsAppeared)
            }
        }
        .padding(.horizontal, ContextMenuStyle.pillSideInset)
        .frame(height: ContextMenuStyle.pillHeight)
    }

    private func pick(_ emoji: String, source: MessageReactionEvent.Source) {
        RecentReactionsStore.record(emoji)
        onPick(emoji, source)
    }

    private func emojiCell(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: layout.itemSize * 0.8))
            .frame(width: layout.itemSize, height: layout.itemSize)
            .background(
                Circle()
                    .fill(selectedColor.opacity(0.25))
                    .opacity(selectedEmojis.contains(emoji) ? 1 : 0)
            )
    }

    private var expandButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onExpandedChange(!isExpanded)
        } label: {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                )
                .frame(width: layout.itemSize, height: layout.itemSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? collapseAccessibilityLabel : expandAccessibilityLabel)
    }
}

/// Telegram при нажатии увеличивает эмоджи; здесь — короткое увеличение под пальцем.
private struct ReactionItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.25 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Раскрытая сетка эмоджи

/// Полоса категорий + ленивая сетка всех эмоджи. Колонок столько же, сколько слотов
/// в быстром ряду (Telegram `itemsPerRow = itemCount`) — сетка продолжает ряд, а не
/// живёт своей шириной.
private struct EmojiGridPanel: View {
    let columns: Int
    let itemSize: CGFloat
    let selectedEmojis: [String]
    let selectedColor: Color
    let onPick: (String) -> Void

    private enum GridSection: Hashable {
        case recent
        case category(EmojiCategory)

        var accessibilityName: String {
            switch self {
            case .recent: return "Recent"
            case .category(let category): return category.accessibilityName
            }
        }

        var symbolName: String {
            switch self {
            case .recent: return "clock"
            case .category(let category): return category.symbolName
            }
        }
    }

    @State private var recents = RecentReactionsStore.load()
    @State private var activeSection: GridSection?

    private var sections: [GridSection] {
        (recents.isEmpty ? [] : [.recent]) + EmojiCategory.allCases.map(GridSection.category)
    }

    private func emojis(in section: GridSection) -> [String] {
        switch section {
        case .recent: return recents
        case .category(let category): return category.emojis
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Rectangle()
                    .fill(ContextMenuStyle.separatorColor)
                    .frame(height: 1 / UIScreen.main.scale)

                categoryStrip(proxy)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(itemSize), spacing: ContextMenuStyle.pillItemSpacing), count: max(columns, 1)),
                        spacing: 6
                    ) {
                        ForEach(sections, id: \.self) { section in
                            // Заголовок секции во всю ширину сетки — якорь для `scrollTo`.
                            Section(header: Color.clear.frame(height: 1).id(section)) {
                                ForEach(emojis(in: section), id: \.self) { emoji in
                                    Button { onPick(emoji) } label: {
                                        Text(emoji)
                                            .font(.system(size: itemSize * 0.78))
                                            .frame(width: itemSize, height: itemSize)
                                            .background(
                                                Circle()
                                                    .fill(selectedColor.opacity(0.25))
                                                    .opacity(selectedEmojis.contains(emoji) ? 1 : 0)
                                            )
                                    }
                                    .buttonStyle(ReactionItemButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ContextMenuStyle.pillSideInset)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func categoryStrip(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(sections, id: \.self) { section in
                Button {
                    activeSection = section
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(section, anchor: .top)
                    }
                } label: {
                    Image(systemName: section.symbolName)
                        .accessibilityLabel(section.accessibilityName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(activeSection == section ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ContextMenuStyle.pillSideInset)
    }
}

// MARK: - Недавние реакции

/// Последние выбранные эмоджи — первая секция раскрытой сетки, как «Недавние» у Telegram.
/// Удобство на устройстве, не данные: живёт в `UserDefaults` и не синхронизируется.
enum RecentReactionsStore {
    private static let key = "ExyteChat.recentReactions"
    static let limit = 24

    static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ emoji: String, defaults: UserDefaults = .standard) {
        var list = load(defaults: defaults).filter { $0 != emoji }
        list.insert(emoji, at: 0)
        defaults.set(Array(list.prefix(limit)), forKey: key)
    }
}

// MARK: - Список действий

struct ContextMenuActionRow: View {
    let title: String
    let icon: Image
    let isDestructive: Bool
    let font: Font
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ContextMenuStyle.actionIconTitleSpacing) {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ContextMenuStyle.actionIconSize - 2, height: ContextMenuStyle.actionIconSize - 2)
                    .frame(width: ContextMenuStyle.actionIconSize, height: ContextMenuStyle.actionIconSize)
                Text(title)
                    .font(font)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(isDestructive ? Color(.systemRed) : .primary)
            .padding(.horizontal, ContextMenuStyle.actionSideInset)
            .frame(height: ContextMenuStyle.actionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ContextMenuRowButtonStyle())
    }
}

/// Подсветка строки под пальцем: скруглённый прямоугольник с отступом, как у Telegram.
private struct ContextMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ContextMenuStyle.highlightColor)
                    .padding(.horizontal, 8)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
    }
}

struct ContextMenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(ContextMenuStyle.separatorColor)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.horizontal, ContextMenuStyle.actionSideInset)
            .padding(.vertical, 6)
    }
}
