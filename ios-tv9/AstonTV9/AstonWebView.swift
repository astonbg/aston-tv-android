import SwiftUI
import WebKit

let ASTON_URL = URL(string: "https://tv.astonserver.eu/tv6/")!
let ASTON_BG = UIColor(red: 7/255, green: 7/255, blue: 10/255, alpha: 1)

struct AstonWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // пази сдвояването (бисквитката) между стартиранията
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = ASTON_BG
        view.scrollView.backgroundColor = ASTON_BG
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.bounces = false
        view.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = view
        view.load(URLRequest(url: ASTON_URL, cachePolicy: .reloadRevalidatingCacheData))
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var failed = false
        @objc func foreground() { if failed { failed = false; webView?.load(URLRequest(url: ASTON_URL)) } }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = navigationAction.request.url else { return decisionHandler(.cancel) }
            if u.scheme == "about" || u.scheme == "blob" || u.scheme == "data" { return decisionHandler(.allow) }
            if u.scheme == "https" && u.host == "tv.astonserver.eu" { return decisionHandler(.allow) }
            if navigationAction.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
            if u.scheme == "http" || u.scheme == "https" { UIApplication.shared.open(u) }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showOffline(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
        func showOffline(_ webView: WKWebView) {
            failed = true
            let html = """
            <html><head><meta name=viewport content="width=device-width,initial-scale=1"></head>
            <body style="background:#07070A;color:#F2F2F6;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
            <div><h2 style="color:#FF2D3D">Aston TV</h2><p>Няма връзка със сървъра.</p>
            <p><a href="https://tv.astonserver.eu/tv6/" style="color:#fff;background:#FF2D3D;padding:12px 22px;border-radius:12px;text-decoration:none">Опитай отново</a></p></div></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
