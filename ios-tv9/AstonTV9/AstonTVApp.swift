import SwiftUI
import AVFoundation
import WebKit

@main
struct AstonTVApp: App {
    @StateObject private var app = AppState.shared
    init() {
        // звукът върви и при безшумен режим и при заключен екран (музикалните канали)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .onOpenURL { url in app.open(url) }
        }
    }
}

/// Общо състояние: WebView, скенер, Studio, сдвояване от линк astontv://pair?rid=...
final class AppState: ObservableObject {
    static let shared = AppState()
    weak var webView: WKWebView?
    var pageReady = false
    var pendingPair: String?
    @Published var showScanner = false
    @Published var showStudio = false

    func open(_ url: URL) {
        guard url.scheme == "astontv", let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rid = c.queryItems?.first(where: { $0.name == "rid" })?.value,
              rid.range(of: "^[A-Za-z0-9_-]{6,40}$", options: .regularExpression) != nil else { return }
        if pageReady, let w = webView { w.evaluateJavaScript("window.__pair&&window.__pair('\(rid)')", completionHandler: nil) }
        else { pendingPair = rid }
    }
    func pageLoaded() {
        pageReady = true
        if let rid = pendingPair, let w = webView {
            pendingPair = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { w.evaluateJavaScript("window.__pair&&window.__pair('\(rid)')", completionHandler: nil) }
        }
    }
    func scanned(_ text: String) {
        showScanner = false
        let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "'", with: "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.webView?.evaluateJavaScript("window.__scanned&&window.__scanned('\(safe)')", completionHandler: nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color(red: 7/255, green: 7/255, blue: 10/255).ignoresSafeArea()
                AstonWebView()
                    // хоризонтално: на целия екран (и зад изреза); вертикално: под часовника/батерията
                    .ignoresSafeArea(.all, edges: landscape ? .all : .bottom)
            }
            .statusBarHidden(landscape)
            .persistentSystemOverlays(landscape ? .hidden : .automatic)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $app.showScanner) { ScannerScreen() }
        .fullScreenCover(isPresented: $app.showStudio) { StudioScreen() }
    }
}
