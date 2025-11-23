# Новые возможности библиотеки чата

## 1. Скролл к определенному сообщению

### Описание
Добавлена возможность программно прокручивать список сообщений к определенному сообщению по его ID.

### Использование

**Option 1: Programmatic scroll (with or without animation)**
```swift
import ExyteChat

ChatView(messages: messages, /* ... */)
    .scrollToMessage(messageId: "message-123", animated: true)
```

**Option 2: Automatic scroll on chat open (WITHOUT animation)**
```swift
ChatView(messages: messages, /* ... */)
    .scrollToMessageOnAppear(firstUnreadMessageId)
```

This is perfect for scrolling to the first unread message when opening a chat. The scroll happens instantly without animation.

### Full Example

```swift
struct ConversationView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        ChatView(
            messages: viewModel.messages,
            chatType: .conversation,
            didSendMessage: viewModel.sendMessage
        )
        // Automatically scroll to first unread on open
        .scrollToMessageOnAppear(viewModel.firstUnreadMessageId)
        // Track read messages
        .enableMessageReadTracking { messageId in
            viewModel.markAsRead(messageId)
        }
    }
}
```

---

## 2. Отслеживание прочитанности сообщений

### Описание
Реализована эффективная система отслеживания видимости сообщений с автоматическим определением максимального видимого сообщения и отправкой данных на бэкенд.

### Архитектура решения

Система использует следующий подход для эффективного отслеживания:

1. **Отслеживание видимости**: Используя делегаты UICollectionView (`willDisplay` и `didEndDisplaying`), система отслеживает какие сообщения находятся на экране.

2. **Фильтрация по времени видимости**: Сообщение считается прочитанным только после того, как оно было видимо определенное минимальное время (по умолчанию 0.5 секунды).

3. **Debouncing**: Вместо отправки запроса на бэкенд при каждом изменении видимости, система накапливает изменения и отправляет их пакетом через определенный интервал (по умолчанию 1 секунда).

4. **Определение максимального сообщения**: Из всех видимых сообщений выбирается самое новое (по дате создания) и его ID отправляется на бэкенд.

5. **Игнорирование собственных сообщений**: Автоматически игнорируются сообщения от текущего пользователя.

### Использование

```swift
import ExyteChat

struct ConversationView: View {
    @State private var messages: [Message] = []

    var body: some View {
        ChatView(messages: messages, /* ... другие параметры ... */)
            .enableMessageReadTracking(
                debounceInterval: 1.0,              // Интервал накопления изменений
                minimumVisibilityDuration: 0.5,     // Минимальное время видимости
                onMessageRead: { messageId in
                    // Вызывается с ID максимального видимого сообщения
                    print("Максимальное видимое сообщение: \(messageId)")

                    // Отправка на бэкенд
                    sendReadReceiptToBackend(messageId: messageId)
                }
            )
    }

    func sendReadReceiptToBackend(messageId: String) {
        // Ваша логика отправки на бэкенд
        // Например:
        // APIClient.markMessageAsRead(messageId: messageId)
    }
}
```

### Параметры конфигурации

#### `debounceInterval` (по умолчанию: 1.0 секунда)
Интервал времени для накопления изменений перед отправкой callback. Это предотвращает слишком частые вызовы при быстром скролле.

**Рекомендации:**
- Для чатов с высокой активностью: 1.0-2.0 секунды
- Для обычных чатов: 0.5-1.0 секунды
- Для real-time индикаторов: 0.3-0.5 секунды

#### `minimumVisibilityDuration` (по умолчанию: 0.5 секунды)
Минимальное время, которое сообщение должно быть видимо на экране, чтобы считаться прочитанным.

**Рекомендации:**
- Для гарантии прочтения: 0.5-1.0 секунды
- Для быстрого реагирования: 0.2-0.5 секунды
- Для строгого контроля: 1.0-2.0 секунды

### Продвинутый пример

```swift
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    var chatView: some View {
        ChatView(messages: messages, /* ... */)
            .enableMessageReadTracking(
                debounceInterval: 1.5,
                minimumVisibilityDuration: 0.7,
                onMessageRead: { [weak self] messageId in
                    self?.handleMessageRead(messageId)
                }
            )
    }

    private func handleMessageRead(_ messageId: String) {
        // Добавляем в очередь для batch-обработки
        Task {
            do {
                try await apiClient.markMessagesAsRead(upTo: messageId)
                print("✅ Сообщения отмечены как прочитанные до: \(messageId)")
            } catch {
                print("❌ Ошибка при отметке сообщений: \(error)")
            }
        }
    }
}
```

### Оптимизация для production

#### 1. Batch-обработка на бэкенде
```swift
// Вместо отправки каждого ID отдельно, накапливайте их
class ReadReceiptManager {
    private var pendingMessageIds: Set<String> = []
    private var batchTimer: Timer?

    func addMessageToRead(_ messageId: String) {
        pendingMessageIds.insert(messageId)
        scheduleBatchSend()
    }

    private func scheduleBatchSend() {
        batchTimer?.invalidate()
        batchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.sendBatch()
        }
    }

    private func sendBatch() {
        guard !pendingMessageIds.isEmpty else { return }
        let ids = Array(pendingMessageIds)
        pendingMessageIds.removeAll()

        // Отправка batch-запроса
        APIClient.markMultipleMessagesAsRead(messageIds: ids)
    }
}
```

#### 2. Локальное кэширование
```swift
class ChatViewModel: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let conversationId: String

    func handleMessageRead(_ messageId: String) {
        // Сохраняем локально
        userDefaults.set(messageId, forKey: "lastReadMessage_\(conversationId)")

        // Отправляем на бэкенд асинхронно
        Task.detached {
            try? await self.apiClient.markMessagesAsRead(upTo: messageId)
        }
    }
}
```

#### 3. Обработка ошибок сети
```swift
func handleMessageRead(_ messageId: String) {
    Task {
        do {
            try await apiClient.markMessagesAsRead(upTo: messageId)
        } catch {
            // Retry с exponential backoff
            retryWithBackoff(messageId: messageId)
        }
    }
}

private func retryWithBackoff(messageId: String, attempt: Int = 0) {
    guard attempt < 3 else { return }

    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        Task {
            do {
                try await self.apiClient.markMessagesAsRead(upTo: messageId)
            } catch {
                self.retryWithBackoff(messageId: messageId, attempt: attempt + 1)
            }
        }
    }
}
```

### Пример интеграции с Firestore

```swift
import FirebaseFirestore

class FirestoreReadReceiptService {
    private let db = Firestore.firestore()

    func markMessagesAsRead(conversationId: String, messageId: String) async throws {
        let userId = Auth.auth().currentUser?.uid ?? ""

        try await db.collection("conversations")
            .document(conversationId)
            .collection("participants")
            .document(userId)
            .setData([
                "lastReadMessageId": messageId,
                "lastReadAt": FieldValue.serverTimestamp()
            ], merge: true)
    }
}

// Использование
ChatView(messages: messages, /* ... */)
    .enableMessageReadTracking { messageId in
        Task {
            try? await FirestoreReadReceiptService()
                .markMessagesAsRead(
                    conversationId: conversationId,
                    messageId: messageId
                )
        }
    }
```

---

## Технические детали

### Алгоритм отслеживания прочитанности

1. **Вход в зону видимости** (`willDisplay`):
   - Сообщение добавляется в Set видимых сообщений
   - Записывается timestamp появления
   - Планируется debounced update

2. **Выход из зоны видимости** (`didEndDisplaying`):
   - Сообщение удаляется из Set видимых
   - Удаляется timestamp
   - Планируется debounced update

3. **Обработка видимых сообщений** (каждые `debounceInterval` секунд):
   - Фильтруются сообщения, видимые >= `minimumVisibilityDuration`
   - Находится максимальное по `createdAt`
   - Если ID изменился, вызывается callback

### Производительность

- **Память**: O(n), где n - количество видимых сообщений (обычно 5-15)
- **CPU**: Минимальная нагрузка благодаря debouncing
- **Сеть**: Оптимизировано через debouncing (максимум 1 запрос в `debounceInterval`)

### Thread Safety

Все операции выполняются на `@MainActor`, обеспечивая безопасность при работе с UI.

---

## Примеры использования

### Базовый чат с отслеживанием прочитанности

```swift
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        ChatView(
            messages: viewModel.messages,
            chatType: .conversation,
            didSendMessage: viewModel.sendMessage
        )
        .enableMessageReadTracking { messageId in
            viewModel.markAsRead(messageId)
        }
    }
}
```

### Скролл к непрочитанному сообщению

```swift
struct ChatView: View {
    @State private var firstUnreadMessageId: String?

    var body: some View {
        ChatView(messages: messages, /* ... */)
            .onAppear {
                if let firstUnread = firstUnreadMessageId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(
                            name: .onScrollToMessage,
                            object: firstUnread
                        )
                    }
                }
            }
            .enableMessageReadTracking { messageId in
                // Обновить firstUnreadMessageId после прочтения
            }
    }
}
```

---

## FAQ

### Q: Как часто вызывается callback?
A: Максимум раз в `debounceInterval` секунд, только при изменении максимального видимого сообщения.

### Q: Что если пользователь быстро скроллит?
A: Благодаря debouncing и `minimumVisibilityDuration`, отправляются только реально прочитанные сообщения.

### Q: Отслеживаются ли мои собственные сообщения?
A: Нет, автоматически игнорируются сообщения где `message.user.isCurrentUser == true`.

### Q: Можно ли отключить отслеживание?
A: Да, просто не вызывайте `.enableMessageReadTracking()` или используйте условный модификатор.

### Q: Как обработать ошибки сети?
A: Реализуйте retry-логику в callback `onMessageRead`. См. примеры выше.

---

## Changelog

### Version 1.0.0
- ✅ Добавлен метод `scrollToMessage(messageId:animated:)` для программного скролла
- ✅ Добавлен `MessageReadTracker` для эффективного отслеживания прочитанности
- ✅ Добавлен метод `enableMessageReadTracking()` для простой интеграции
- ✅ Оптимизирован алгоритм с debouncing и минимальным временем видимости
