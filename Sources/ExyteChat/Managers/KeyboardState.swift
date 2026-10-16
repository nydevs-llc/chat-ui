//
//  Created by Alex.M on 02.10.2023.
//

import Foundation
import Combine
import UIKit

@MainActor
public final class KeyboardState: ObservableObject {
    @Published private(set) public var isShown: Bool = false
    @Published private(set) public var keyboardFrame: CGRect = .zero
    
    private var subscriptions = Set<AnyCancellable>()

    init() {
        subscribeKeyboardNotifications()
    }

    /// Requests the dismissal of the current / active keyboard
    public func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension KeyboardState {
    func subscribeKeyboardNotifications() {
        let pub = Publishers.Merge(
            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue }
                .map { $0.cgRectValue },

            NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in .zero }
        )
        .receive(on: RunLoop.main)
        
        // `assign(to:on: self)` держит `self` сильно: подписка лежит в `subscriptions`
        // самого объекта — цикл, и каждый `KeyboardState` (по одному на `ChatView` и
        // на каждое открытие `MessageMenu`) жил вечно вместе с двумя наблюдателями
        // NotificationCenter. Поэтому `sink` со слабым `self`.
        pub.sink { [weak self] frame in
            guard let self else { return }
            self.keyboardFrame = frame
            self.isShown = frame != .zero
        }
        .store(in: &subscriptions)
    }
}
