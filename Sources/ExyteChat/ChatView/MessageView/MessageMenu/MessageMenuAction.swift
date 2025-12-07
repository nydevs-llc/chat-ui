//
//  MessageMenuAction.swift
//  Chat
//
//  Created by Bohdan Yankivskyi on 05.08.2025.
//

import SwiftUI

public protocol MessageMenuAction: Equatable, CaseIterable, Hashable {
    func title() -> String
    func icon() -> Image
    func type() -> MessageMenuActionType

    static func menuItems(for message: Message) -> [Self]
}

public extension MessageMenuAction {
    static func menuItems(for message:Message) -> [Self] {
        Self.allCases.map { $0 }
    }
}

public enum MessageMenuActionType: Equatable {
    case edit, delete, reply, copy, information, forward
}

public enum DefaultMessageMenuAction: MessageMenuAction {
    case reply
    case edit(saveClosure: (String) -> Void)
    
    public func title() -> String {
        switch self {
        case .reply:
            "Reply"
        case .edit:
            "Edit"
        }
    }
    
    public func icon() -> Image {
        switch self {
        case .reply:
            Image("")
        case .edit:
            Image("")
        }
    }
    
    public func type() -> MessageMenuActionType {
        switch self {
        case .reply:
            return .reply
        case .edit:
            return .edit
        }
    }

    public static func == (lhs: DefaultMessageMenuAction, rhs: DefaultMessageMenuAction) -> Bool {
        switch (lhs, rhs) {
        case (.reply, .reply):
            return true
        case (.edit, .edit):
            return true
        default:
            return false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
         switch self {
         case .reply:
             hasher.combine("reply")
         case .edit:
             hasher.combine("edit")
         }
     }

    public static var allCases: [DefaultMessageMenuAction] = [
        .reply,
        .edit(saveClosure: { _ in })
    ]
}
