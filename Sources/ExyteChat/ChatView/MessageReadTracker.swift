//
//  MessageReadTracker.swift
//  Chat
//
//  Created by Claude on 23.11.2025.
//

import Foundation
import Combine

/// Efficient message read tracking with debouncing
@MainActor
public final class MessageReadTracker: ObservableObject {

    /// Callback type for reporting the maximum visible message ID
    public typealias ReadStatusCallback = (String) -> Void

    /// Currently visible message IDs with their metadata
    private var visibleMessages: Set<VisibleMessage> = []

    /// Last reported message ID to avoid duplicate callbacks
    private var lastReportedMessageId: String?

    /// Callback to be called when read status changes
    private var readStatusCallback: ReadStatusCallback?

    /// Debounce timer to batch updates
    private var debounceTimer: Timer?

    /// Debounce interval in seconds (default: 1.0 second)
    private let debounceInterval: TimeInterval

    /// Minimum visibility duration before considering a message as read (default: 0.5 seconds)
    private let minimumVisibilityDuration: TimeInterval

    /// Visibility timestamps for messages
    private var visibilityTimestamps: [String: Date] = [:]

    /// Whether tracking is currently enabled
    private var isEnabled: Bool = false

    /// Messages that are pending visibility check
    private var pendingMessages: Set<String> = []

    public init(
        debounceInterval: TimeInterval = 1.0,
        minimumVisibilityDuration: TimeInterval = 0.5
    ) {
        self.debounceInterval = debounceInterval
        self.minimumVisibilityDuration = minimumVisibilityDuration
    }

    deinit {
        debounceTimer?.invalidate()
    }

    /// Enable tracking with a callback
    public func enable(callback: @escaping ReadStatusCallback) {
        self.readStatusCallback = callback
        self.isEnabled = true
    }

    /// Disable tracking
    public func disable() {
        isEnabled = false
        debounceTimer?.invalidate()
        debounceTimer = nil
        visibleMessages.removeAll()
        visibilityTimestamps.removeAll()
        pendingMessages.removeAll()
    }

    /// Called when a message becomes visible
    public func messageDidAppear(messageId: String, createdAt: Date) {
        guard isEnabled else { return }

        let message = VisibleMessage(id: messageId, createdAt: createdAt)
        visibleMessages.insert(message)
        visibilityTimestamps[messageId] = Date()
        pendingMessages.insert(messageId)

        scheduleUpdate()
    }

    /// Called when a message disappears from view
    public func messageDidDisappear(messageId: String) {
        guard isEnabled else { return }

        visibleMessages.removeAll { $0.id == messageId }
        visibilityTimestamps.removeValue(forKey: messageId)
        pendingMessages.remove(messageId)

        scheduleUpdate()
    }

    /// Schedule a debounced update
    private func scheduleUpdate() {
        debounceTimer?.invalidate()

        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processVisibleMessages()
            }
        }
    }

    /// Process visible messages and determine which ones should be marked as read
    private func processVisibleMessages() {
        guard isEnabled else { return }

        // Filter messages that have been visible long enough
        let now = Date()
        let readMessages = visibleMessages.filter { message in
            guard let timestamp = visibilityTimestamps[message.id] else { return false }
            return now.timeIntervalSince(timestamp) >= minimumVisibilityDuration
        }

        guard !readMessages.isEmpty else { return }

        // Find the maximum message (latest by creation date)
        let maxMessage = readMessages.max { $0.createdAt < $1.createdAt }

        guard let maxMessage = maxMessage else { return }

        // Only call callback if this is a new maximum
        if lastReportedMessageId != maxMessage.id {
            lastReportedMessageId = maxMessage.id
            readStatusCallback?(maxMessage.id)

            // Remove from pending
            pendingMessages.remove(maxMessage.id)
        }
    }

    /// Force immediate update without debouncing
    public func forceUpdate() {
        debounceTimer?.invalidate()
        processVisibleMessages()
    }

    /// Reset the tracker state
    public func reset() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        visibleMessages.removeAll()
        visibilityTimestamps.removeAll()
        pendingMessages.removeAll()
        lastReportedMessageId = nil
    }
}

// MARK: - Supporting Types

extension MessageReadTracker {
    struct VisibleMessage: Hashable {
        let id: String
        let createdAt: Date

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: VisibleMessage, rhs: VisibleMessage) -> Bool {
            lhs.id == rhs.id
        }
    }
}
