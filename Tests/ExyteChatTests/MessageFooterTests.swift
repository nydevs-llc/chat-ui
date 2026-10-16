import Testing
@testable import ExyteChat

/// Подвал сообщения обязан участвовать в `==`/`hash`: ячейка ленты
/// переконфигурируется только по неравенству строк (`SonataUIList.apply`).
struct MessageFooterTests {
    private let user = User(id: "me", name: "Me", avatarURL: nil, avatarCachedImage: nil, isCurrentUser: true)

    @Test func footerChange_makesMessagesUnequal() {
        let plain = Message(id: "1", user: user, text: "hi")
        let withFooter = Message(id: "1", user: user, text: "hi", footer: MessageFooter(id: "chip"))
        #expect(plain != withFooter)
    }

    @Test func sameFooter_keepsMessagesEqual() {
        let a = Message(id: "1", user: user, text: "hi", footer: MessageFooter(id: "chip"))
        let b = Message(id: "1", user: user, text: "hi", footer: MessageFooter(id: "chip"))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
