#if os(macOS)
import AppKit

@main
enum ConvertAllApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate  // weak reference — keep `delegate` alive for the app's lifetime
        withExtendedLifetime(delegate) { app.run() }
    }
}
#else
// The app is macOS-only; this stub lets `swift test` build the core on Linux CI.
@main
enum ConvertAllApp {
    static func main() { print("ConvertAll is a macOS app.") }
}
#endif
