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
        Task { @MainActor in
            for cookie in cookies { await config.websiteDataStore.httpCookieStore.setCookie(cookie) }
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
        web.evaluateJavaScript("stop()",completionHandler:nil)
        web.configuration.userContentController.removeScriptMessageHandler(forName:"videoState")
        web.stopLoading()
    }
    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        weak var engine:TVEngine?
        var playback:GatewayPlayback
        var ready=false
        init(_ engine:TVEngine,_ playback:GatewayPlayback) {self.engine=engine;self.playback=playback}
        func webView(_ web:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
            guard let url=action.request.url else {decisionHandler(.cancel);return}
            let same=url.scheme==playback.server.scheme && url.host==playback.server.host && url.port==playback.server.port
            decisionHandler(same || url.scheme=="blob" || url.scheme=="about" ? .allow:.cancel)
        }
        func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {ready=true;start(web)}
        func start(_ web:WKWebView) {
            guard let data=try? JSONSerialization.data(withJSONObject:[playback.url,playback.name,playback.channel]),
                  let args=String(data:data,encoding:.utf8) else {return}
            let script="""
            (function(){
              if(typeof playback!=='function')throw Error('Gateway player unavailable');
              var a=\(args),v=document.getElementById('video');
              if(!v)throw Error('Video surface missing');
              var style=document.getElementById('aston-mobile-video');
              if(!style){style=document.createElement('style');style.id='aston-mobile-video';
                style.textContent='body{margin:0!important;background:#000!important;overflow:hidden!important}body>*{visibility:hidden!important}body>video{visibility:visible!important;position:fixed!important;inset:0!important;width:100%!important;height:100%!important;object-fit:contain!important;background:#000!important}';document.head.appendChild(style);}
              document.body.appendChild(v);v.setAttribute('playsinline','');
              if(!v.dataset.astonEvents){v.dataset.astonEvents='1';
                ['playing','pause','waiting','error'].forEach(function(event){v.addEventListener(event,function(){window.webkit.messageHandlers.videoState.postMessage({state:event});});});}
              playback(a[0],a[1],null,'mpegts',a[2]);
            })();
            """
            web.evaluateJavaScript(script) { [weak self] _,error in
                if error != nil {self?.engine?.status="Уеб плейърът не се зареди"}
            }
        }
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
            guard let engine,engine.webPlayback==playback,
                  let data=message.body as? [String:String],let state=data["state"] else{return}
            engine.isPlaying=state=="playing"
            switch state {
            case "playing":engine.status="НА ЖИВО"
            case "pause":engine.status="Пауза"
            case "waiting":engine.status="Буфериране…"
            case "error":engine.status="Грешка при възпроизвеждане"
            default:break
            }
        }
        func webView(_ web:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
            engine?.status="Gateway плейърът е недостъпен"
        }
    }
}
