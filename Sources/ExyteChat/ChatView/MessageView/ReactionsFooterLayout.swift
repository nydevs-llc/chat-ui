//
//  ReactionsFooterLayout.swift
//

import SwiftUI

/// Отступы зоны реакций в текстовом пузыре (Telegram-поведение, свои числа).
enum ReactionsFooterMetrics {
    /// Текст → первая строка чипов.
    static let textToChipsSpacing: CGFloat = 6
    /// Между чипами в строке.
    static let chipSpacing: CGFloat = 4
    /// Между строками чипов при переносе.
    static let rowSpacing: CGFloat = 4
    /// Минимальный зазор между последним чипом и временем/статусом.
    static let timeSpacing: CGFloat = 8
    /// Низ последней строки чипов → край пузыря.
    static let bottomInset: CGFloat = 6
}

/// Раскладка текстового пузыря с реакциями, как в Telegram.
///
/// Элементы: первый — текст, последний — время/статус (может быть нулевого
/// размера, например у входящего без времени; передавать ОДНИМ вью — обёрткой
/// `ZStack`, чтобы пустое время не «съело» последний чип), между ними — чипы.
///
/// - Текст сверху, своей шириной.
/// - Под ним чипы слева направо с переносом по ширине пузыря.
/// - Время/статус — в конце последней строки чипов, прижато к правому краю
///   пузыря; не помещается — отдельной строкой справа.
/// - Ширина = max(текст, самая широкая строка чипов со временем) — пузырь не
///   растягивается на всю доступную ширину.
@available(iOS 16.0, *)
struct ReactionsFooterLayout: Layout {
    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        /// Время стоит в этой строке (последней).
        var hasTime = false
    }

    struct Arrangement {
        var textSize: CGSize = .zero
        var timeSize: CGSize = .zero
        var sizes: [CGSize] = []
        var rows: [Row] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Void { () }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(maxWidth: proposal.width ?? bounds.width, subviews: subviews)
        guard !subviews.isEmpty else { return }

        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: a.textSize.width, height: a.textSize.height)
        )

        var y = bounds.minY + a.textSize.height + (a.rows.isEmpty ? 0 : ReactionsFooterMetrics.textToChipsSpacing)
        for row in a.rows {
            var x = bounds.minX
            for index in row.indices {
                let size = a.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + ReactionsFooterMetrics.chipSpacing
            }
            if row.hasTime, subviews.count > 1 {
                subviews[subviews.count - 1].place(
                    at: CGPoint(x: bounds.maxX - a.timeSize.width, y: y + (row.height - a.timeSize.height) / 2),
                    proposal: ProposedViewSize(a.timeSize)
                )
            }
            y += row.height + ReactionsFooterMetrics.rowSpacing
        }
    }

    private func arrange(maxWidth proposedWidth: CGFloat?, subviews: Subviews) -> Arrangement {
        var a = Arrangement()
        guard let first = subviews.first else { return a }
        let maxWidth = (proposedWidth.map { $0.isFinite && $0 > 0 ? $0 : .infinity }) ?? .infinity

        a.textSize = first.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
        a.sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        let hasTimeSlot = subviews.count >= 2
        let chipRange = hasTimeSlot ? 1..<(subviews.count - 1) : 1..<1
        a.timeSize = hasTimeSlot ? a.sizes[subviews.count - 1] : .zero
        let showsTime = a.timeSize.width > 0 && a.timeSize.height > 0

        var rows: [Row] = []
        var current = Row()
        for index in chipRange {
            let size = a.sizes[index]
            let added = current.indices.isEmpty ? size.width : current.width + ReactionsFooterMetrics.chipSpacing + size.width
            if !current.indices.isEmpty && added > maxWidth {
                rows.append(current)
                current = Row()
                current.width = size.width
            } else {
                current.width = added
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }

        if showsTime {
            let last = rows.count - 1
            let withTime = last >= 0
                ? rows[last].width + ReactionsFooterMetrics.timeSpacing + a.timeSize.width
                : .infinity
            if last >= 0, withTime <= maxWidth {
                rows[last].width = withTime
                rows[last].height = max(rows[last].height, a.timeSize.height)
                rows[last].hasTime = true
            } else {
                var timeRow = Row()
                timeRow.width = a.timeSize.width
                timeRow.height = a.timeSize.height
                timeRow.hasTime = true
                rows.append(timeRow)
            }
        }
        a.rows = rows

        let rowsWidth = rows.map(\.width).max() ?? 0
        let rowsHeight = rows.map(\.height).reduce(0, +)
            + CGFloat(max(rows.count - 1, 0)) * ReactionsFooterMetrics.rowSpacing
        let width = max(a.textSize.width, rowsWidth)
        let height = a.textSize.height
            + (rows.isEmpty ? 0 : ReactionsFooterMetrics.textToChipsSpacing + rowsHeight)
        a.size = CGSize(width: maxWidth.isFinite ? min(width, maxWidth) : width, height: height)
        return a
    }
}
