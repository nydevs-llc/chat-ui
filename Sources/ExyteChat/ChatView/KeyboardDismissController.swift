//
//  KeyboardDismissController.swift
//

import UIKit

public extension Notification.Name {
    /// Тап по ленте сообщений. Клавиатуру лента убирает сама; композер по этому
    /// сигналу закрывает свои панели на месте клавиатуры (эмодзи/стикеры) —
    /// как в Telegram, где тап по истории закрывает любой ввод.
    static let chatListTapped = Notification.Name("chatListTapped")
}

/// Клавиатура уходит как в Telegram: тапом по ленте и смахиванием ленты вниз
/// (интерактивно — граница клавиатуры идёт за пальцем, `keyboardDismissMode`).
///
/// Раньше ленту убирала только SwiftUI-`TapGesture` в `ChatView`, которая
/// сбрасывает `GlobalFocusState`, — а у своего композера приложения поле с этим
/// состоянием не связано, и клавиатура не уходила вовсе.
final class KeyboardDismissController: NSObject, UIGestureRecognizerDelegate {

    func attach(to collectionView: UICollectionView) {
        collectionView.keyboardDismissMode = .interactive

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        // Тап не отнимаем у ячеек: кнопки, цитаты и реакции срабатывают как раньше.
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let collectionView = recognizer.view as? UICollectionView,
              isInsideVisibleList(recognizer.location(in: collectionView), of: collectionView)
        else { return }
        recognizer.view?.window?.endEditing(true)
        NotificationCenter.default.post(name: .chatListTapped, object: nil)
    }

    /// Панель ввода плавает поверх ленты и нарисована SwiftUI без своих UIView:
    /// тап по её кнопкам (смайлик, микрофон) доходит и до ленты. Такой тап —
    /// не «тап по ленте»: иначе кнопка смайлика открывала бы панель стикеров,
    /// а этот же тап тут же её закрывал. Лента видна выше своего нижнего отступа
    /// (панель ввода + клавиатура).
    private func isInsideVisibleList(_ point: CGPoint, of collectionView: UICollectionView) -> Bool {
        let isFlipped = collectionView.transform.d < 0
        let bottomInset = isFlipped ? collectionView.contentInset.top : collectionView.contentInset.bottom
        let visibleHeight = collectionView.bounds.height - bottomInset
        // В перевёрнутой ленте визуальный низ — у меньших y в её координатах.
        let distanceFromVisualTop = isFlipped
            ? collectionView.bounds.maxY - point.y
            : point.y - collectionView.bounds.minY
        return distanceFromVisualTop < visibleHeight
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
