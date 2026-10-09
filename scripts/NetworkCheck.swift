import Foundation

// Public homepage only. This never reads the keychain or a private subscription.
@main
struct NetworkCheck {
    static func main() async {
        do {
            let text = try await FeedClient().fetch(URL(string: "https://bb.cuhk.edu.cn/")!)
            print("Public Blackboard HTTPS request succeeded (\(text.utf8.count) bytes).")
        } catch { print(error.localizedDescription) }
    }
}
