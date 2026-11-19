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
        web.evaluateJavaScript("stop()",completionHandler:nil)
        web.configuration.userContentController.removeScriptMessageHandler(forName:"videoState")
        web.stopLoading()
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
        func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {ready=true;start(web)}
        func start(_ web:WKWebView) {
            guard let data=try? JSONSerialization.data(withJSONObject:[playback.url,playback.name,playback.channel]),
                  let args=String(data:data,encoding:.utf8) else {return}
            let script="""
            (function(){
              if(typeof playback!=='function')throw Error('Gateway player unavailable');
              var a=\(args),v=document.getElementById('video');
              if(!v)throw Error('Video surface missing');
              // CSSOM properties work with the Gateway's strict style-src policy.
              document.body.style.margin='0';document.body.style.background='#000';document.body.style.overflow='hidden';
              Array.from(document.body.children).forEach(function(node){if(node!==v)node.style.visibility='hidden';});
              document.body.appendChild(v);v.setAttribute('playsinline','');
              v.style.visibility='visible';v.style.position='fixed';v.style.inset='0';v.style.width='100%';v.style.height='100%';v.style.objectFit='contain';v.style.background='#000';
              if(!v.dataset.astonEvents){v.dataset.astonEvents='1';
                ['playing','pause','waiting','error'].forEach(function(event){v.addEventListener(event,function(){window.webkit.messageHandlers.videoState.postMessage({state:event});});});
                v.addEventListener('timeupdate',function(){var r=v.seekable;window.webkit.messageHandlers.videoState.postMessage({seekable:!!(r.length&&r.end(r.length-1)-r.start(0)>2)});});
                var statusNode=document.getElementById('status');
                if(statusNode)new MutationObserver(function(){if(/грешка|неподдържан|липсва|изтече/i.test(statusNode.textContent))window.webkit.messageHandlers.videoState.postMessage({state:'error'});}).observe(statusNode,{childList:true,characterData:true,subtree:true});}
              playback(a[0],a[1],null,'mpegts',a[2]);
            })();
            """
            web.evaluateJavaScript(script) { [weak self] _,error in
                if error != nil {self?.engine?.status="Уеб плейърът не се зареди"}
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
            default:break
            }
        }
        func webView(_ web:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
            engine?.status="Gateway плейърът е недостъпен"
        }
    }
}

