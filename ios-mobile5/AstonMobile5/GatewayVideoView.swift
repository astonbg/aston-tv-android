import SwiftUI
import WebKit

struct GatewayPlayback: Equatable {
    let server: URL
    let url: String
    let name: String
    let channel: String
}

// Use the deployed Gateway's MPEG-TS implementation, as in Premium 4.1.1.
// Keep the native mobile navigation; expose only the actual video surface.
struct GatewayVideoView: UIViewRepresentable {
    @ObservedObject var engine: TVEngine
    let playback: GatewayPlayback
    func makeCoordinator() -> Coordinator { Coordinator(engine, playback) }
    func makeUIView(context: Context) -> WKWebView {
        let config=WKWebViewConfiguration()
        config.allowsInlineMediaPlayback=true
        config.mediaTypesRequiringUserActionForPlayback=[]
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator,name:"videoState")
        let web=WKWebView(frame:.zero,configuration:config)
        web.isOpaque=false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled=false
        web.navigationDelegate=context.coordinator
        engine.webView=web
        let cookies=HTTPCookieStorage.shared.cookies(for:playback.server) ?? []
        let coordinator=context.coordinator
        Task { @MainActor in
            for cookie in cookies { await config.websiteDataStore.httpCookieStore.setCookie(cookie) }
            guard coordinator.active else { return }
            web.load(URLRequest(url:playback.server))
        }
        return web
    }
    func updateUIView(_ web:WKWebView,context:Context) {
        if context.coordinator.playback != playback {
            context.coordinator.playback=playback
            if context.coordinator.ready { context.coordinator.start(web) }
        }
    }
    static func dismantleUIView(_ web:WKWebView,coordinator:Coordinator) {
        coordinator.active=false
        web.evaluateJavaScript("document.getElementById('stop')?.click()",completionHandler:nil)
        web.configuration.userContentController.removeScriptMessageHandler(forName:"videoState")
        web.stopLoading()
        web.loadHTMLString("",baseURL:nil)
    }
    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        weak var engine:TVEngine?
        var playback:GatewayPlayback
        var ready=false
        var active=true
        init(_ engine:TVEngine,_ playback:GatewayPlayback) {self.engine=engine;self.playback=playback}
        func webView(_ web:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
            guard let url=action.request.url else {decisionHandler(.cancel);return}
            let same=url.scheme==playback.server.scheme && url.host==playback.server.host && url.port==playback.server.port
            decisionHandler(same || url.scheme=="blob" || url.scheme=="about" ? .allow:.cancel)
        }
        func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {guard active else{return};ready=true;start(web)}
        func start(_ web:WKWebView) {
            guard active,
                  let data=try? JSONSerialization.data(withJSONObject:["channel":playback.channel,"requestId":UUID().uuidString]),
                  let args=String(data:data,encoding:.utf8),
                  let resource=Bundle.main.url(forResource:"GatewayPlayback",withExtension:"js"),
                  let template=try? String(contentsOf:resource,encoding:.utf8) else {
                engine?.status="Липсва компонентът на плейъра";return
            }
            let script=template.replacingOccurrences(of:"__ASTON_REQUEST__",with:args)
            web.evaluateJavaScript(script) { [weak self] _,error in
                if let error=error as NSError? {
                    self?.engine?.status="Грешка при стартиране на плейъра (\(error.code))"
                }
            }
        }
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
            guard active,let engine,engine.webPlayback==playback,
                  let data=message.body as? [String:Any] else{return}
            if let seekable=data["seekable"] as? Bool,seekable != engine.hasSeek {engine.hasSeek=seekable}
            guard let state=data["state"] as? String else{return}
            engine.isPlaying=state=="playing"
            switch state {
            case "playing":engine.status="НА ЖИВО"
            case "pause":engine.status="Пауза"
            case "waiting":engine.status="Буфериране…"
            case "error":engine.status="Грешка при възпроизвеждане"
            case "pairing":engine.status="Gateway изисква повторно сдвояване"
            case "missing-channel":engine.status="Каналът не се появи в Gateway. Опитай отново."
            default:break
            }
        }
        func webView(_ web:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
            engine?.status="Gateway плейърът е недостъпен"
        }
    }
}
