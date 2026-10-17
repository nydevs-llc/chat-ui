//
//  SwipeToReplyController.swift
//
//  Свайп сообщения влево — ответ на него (Telegram). Поведение и числа — по
//  описанию `MESSAGE_ANIMATIONS_SPEC.md`, A18 (код Telegram не использован).
//

import UIKit

/// Один UIKit-pan на всю ленту.
///
/// - Старт только влево и только горизонтально: `|dx| > 2` и `2·|dy| < |dx|`;
///   вертикальная прокрутка до этого не теряется, после — отменяется.
/// - Строка едет за пальцем до порога (45 pt входящее, 60 pt исходящее), дальше —
///   с сопротивлением `порог + (1 − 1/(x·0.4/100 + 1))·100`, но не больше 180 pt.
/// - На пересечении порога — лёгкий щелчок (Лев 17.10: «щелчок лёгкий»), справа
///   проявляется иконка ответа 33 pt (масштаб 0.65 → 1, на пороге — «волна»).
/// - Отпустили за порогом — ответ; строка возвращается пружиной 0.3 с.
@MainActor
final class SwipeToReplyController: NSObject, UIGestureRecognizerDelegate {

    struct Target {
        let isOutgoing: Bool
        let onReply: () -> Void
    }

    static let incomingThreshold: CGFloat = 45
    static let outgoingThreshold: CGFloat = 60
    static let maxOffset: CGFloat = 180
    static let iconSide: CGFloat = 33

    /// Сообщение под пальцем, на которое можно ответить (иначе `nil`).
    var targetAt: (IndexPath) -> Target? = { _ in nil }

    private weak var collectionView: UICollectionView?
    private lazy var pan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()

    private weak var cell: UICollectionViewCell?
    private var target: Target?
    private var threshold: CGFloat = SwipeToReplyController.incomingThreshold
    private var isPastThreshold = false
    private var iconView: UIView?
    /// Лента перевёрнута (`transform` y = −1) — иконку в ячейке переворачиваем обратно.
    private var iconBase: CGAffineTransform = .identity
    private var haptic: UIImpactFeedbackGenerator?

    func attach(to cv: UICollectionView) {
        collectionView = cv
        cv.addGestureRecognizer(pan)
    }

    // MARK: - Gesture

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let cv = collectionView else { return true }
        let t = pan.translation(in: cv)
        // Только влево и заметно горизонтально — диагональный скролл не перехватываем.
        // Пан спрашивает разрешения на первом же сдвиге (часто 1 pt) — тогда
        // направление берём по скорости.
        let v = pan.velocity(in: cv)
        let d = abs(t.x) >= 2 ? t : v
        guard d.x < 0, 2 * abs(d.y) < abs(d.x) else { return false }
        // Касание у левого края — системный «назад».
        guard pan.location(in: cv).x - t.x > 8 else { return false }
        guard let indexPath = cv.indexPathForItem(at: pan.location(in: cv)),
              let target = targetAt(indexPath),
              let cell = cv.cellForItem(at: indexPath) else { return false }
        self.target = target
        self.cell = cell
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // До начала свайпа скролл живёт параллельно; на `.began` он отменяется.
        other === collectionView?.panGestureRecognizer
    }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard let cv = collectionView else { return }
        switch pan.state {
        case .began:
            threshold = (target?.isOutgoing ?? false) ? Self.outgoingThreshold : Self.incomingThreshold
            isPastThreshold = false
            haptic = UIImpactFeedbackGenerator(style: .light)
            haptic?.prepare()
            // Вертикальная прокрутка на время свайпа — нет.
            cv.panGestureRecognizer.isEnabled = false
            cv.panGestureRecognizer.isEnabled = true
            cv.isScrollEnabled = false
            installIcon()
            update(translation: pan.translation(in: cv).x)
        case .changed:
            update(translation: pan.translation(in: cv).x)
        case .ended:
            let reply = isPastThreshold
            finish()
            if reply { target?.onReply() }
            target = nil
        case .cancelled, .failed:
            finish()
            target = nil
        default:
            break
        }
    }

    // MARK: - Movement

    /// Сдвиг строки по смещению пальца (`dx` ≤ 0).
    static func offset(for dx: CGFloat, threshold: CGFloat) -> CGFloat {
        let x = max(0, -dx)
        guard x > threshold else { return x }
        let over = x - threshold
        return min(maxOffset, threshold + (1 - 1 / (over * 0.4 / 100 + 1)) * 100)
    }

    private func update(translation dx: CGFloat) {
        guard let cell else { return }
        let offset = Self.offset(for: dx, threshold: threshold)
        // `transform` у contentView занят переворотом ленты — двигаем подслои.
        cell.contentView.layer.sublayerTransform = CATransform3DMakeTranslation(-offset, 0, 0)

        let progress = min(1, offset / threshold)
        if let iconView {
            iconView.alpha = progress
            let scale = 0.65 + 0.35 * progress
            iconView.transform = iconBase.scaledBy(x: scale, y: scale)
        }

        let past = offset >= threshold
        if past != isPastThreshold {
            isPastThreshold = past
            if past {
                haptic?.impactOccurred()
                haptic?.prepare()
                pulseIcon()
            }
        }
    }

    private func finish() {
        collectionView?.isScrollEnabled = true
        guard let cell else { return }
        let icon = iconView
        iconView = nil
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let animations = {
            cell.contentView.layer.sublayerTransform = CATransform3DIdentity
            icon?.alpha = 0
            icon?.transform = (icon?.transform ?? .identity).scaledBy(x: 0.2, y: 0.2)
        }
        let completion: (Bool) -> Void = { _ in icon?.removeFromSuperview() }
        // `sublayerTransform` — свойство слоя: UIView-анимация его не ведёт, нужна CA.
        let from = cell.contentView.layer.presentation()?.sublayerTransform ?? cell.contentView.layer.sublayerTransform
        if reduceMotion {
            let fade = CABasicAnimation(keyPath: "sublayerTransform")
            fade.fromValue = NSValue(caTransform3D: from)
            fade.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            fade.duration = 0.2
            cell.contentView.layer.add(fade, forKey: "swipeToReplyReturn")
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveLinear], animations: animations, completion: completion)
        } else {
            let spring = CASpringAnimation(keyPath: "sublayerTransform")
            spring.fromValue = NSValue(caTransform3D: from)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.damping = 26
            spring.stiffness = 440
            spring.mass = 1
            spring.duration = spring.settlingDuration
            cell.contentView.layer.add(spring, forKey: "swipeToReplyReturn")
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: animations, completion: completion)
        }
        cell.contentView.layer.sublayerTransform = CATransform3DIdentity
        self.cell = nil
        haptic = nil
    }

    // MARK: - Icon

    private func installIcon() {
        guard let cell else { return }
        iconView?.removeFromSuperview()
        let side = Self.iconSide
        let icon = UIView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        icon.isUserInteractionEnabled = false
        icon.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        icon.layer.cornerRadius = side / 2
        let glyph = UIImageView(image: UIImage(
            systemName: "arrowshape.turn.up.left.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        ))
        glyph.tintColor = .white
        glyph.sizeToFit()
        glyph.center = CGPoint(x: side / 2, y: side / 2)
        icon.addSubview(glyph)
        // В ячейке, а не в contentView: тот сдвигается и перевёрнут.
        icon.center = CGPoint(x: cell.bounds.maxX - 12 - side / 2, y: cell.bounds.midY)
        iconBase = (collectionView?.transform.d ?? 1) < 0 ? CGAffineTransform(scaleX: 1, y: -1) : .identity
        icon.transform = iconBase
        icon.alpha = 0
        cell.addSubview(icon)
        iconView = icon
    }

    /// «Волна» на пороге: 1 → 1.1 за 0.2 с, обратно за 0.15 с.
    private func pulseIcon() {
        guard let iconView, !UIAccessibility.isReduceMotionEnabled else { return }
        let base = iconBase
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            iconView.transform = base.scaledBy(x: 1.1, y: 1.1)
        } completion: { _ in
            UIView.animate(withDuration: 0.15) {
                iconView.transform = base
            }
        }
    }
}
