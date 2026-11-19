import SwiftUI
import WebKit

@MainActor
final class AstonBrowser: ObservableObject {
    static let local = URL(string: "http://10.10.10.179:8424/")!
    static let remote = URL(string: "https://tv.astonserver.eu/")!
    @Published var isLoading = false
    @Published var error: String?
    @Published var showServers = false
    @Published var showChannels = false
    @Published var channelItems: [TVChannel] = []
    @Published var isExternal = false
    weak var webView: WKWebView?
    var url: URL {
        let s = UserDefaults.standard.string(forKey: "aston_server") ?? Self.local.absoluteString
        return s == Self.remote.absoluteString ? Self.remote : Self.local
    }
    func load(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: "aston_server")
        webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }
    func run(_ script: String, completion: ((Any?) -> Void)? = nil) {
        webView?.evaluateJavaScript(script) { value, _ in completion?(value) }
    }
    func channel(_ step: Int) {
        let target = step < 0 ? "previousChannel" : "nextChannel"
        run("(function(){var b=document.getElementById('\(target)');if(b){b.click();return true;}return false;})()")
    }
    func seek(_ seconds: Int) {
        run("(function(){var v=document.querySelector('video');if(!v||!v.seekable||!v.seekable.length)return false;try{var a=v.seekable.start(0),b=v.seekable.end(v.seekable.length-1);if(b-a<2)return false;v.currentTime=Math.min(b,Math.max(a,v.currentTime+\(seconds)));return true;}catch(e){return false;}})()")
    }
    func playPause() {
        run("(function(){var v=document.querySelector('video');if(!v)return; if(v.paused)v.play().catch(function(){});else v.pause();})()")
    }
    func open(_ name: String) {
        let safe = name.replacingOccurrences(of: "'", with: "")
        run("(function(){var b=document.querySelector('[data-view=\"\(safe)\"]');if(b)b.click();var p=document.getElementById('\(safe)');if(!b&&p)p.scrollIntoView({block:'start',behavior:'smooth'});})()")
    }
    func fullScreen() {
        run("(function(){var v=document.querySelector('video');if(v&&v.webkitEnterFullscreen){v.webkitEnterFullscreen();return;}var b=document.getElementById('playerExpand');if(b)b.click();})()")
    }
    func loadChannelList() {
        run("(function(){var els=document.querySelectorAll('#channelRail [data-id]');return JSON.stringify(Array.from(els).map(function(e){return {id:e.getAttribute('data-id'),name:e.getAttribute('title')||e.textContent.trim()};}));})()") { [weak self] value in
            guard let self, let string = value as? String, let data = string.data(using: .utf8),
                  let result = try? JSONDecoder().decode([TVChannel].self, from: data) else { return }
            self.channelItems = result
            self.showChannels = true
        }
    }
    func select(_ channel: TVChannel) {
        let encoded = String(data: (try? JSONSerialization.data(withJSONObject: [channel.id], options: .fragmentsAllowed)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        run("(function(){var id=\(encoded)[0];var els=document.querySelectorAll('[data-id]');for(var i=0;i<els.length;i++){if(els[i].getAttribute('data-id')===id){els[i].click();break;}}})()")
        showChannels = false
    }
    func back() {
        run("(function(){try{var m=document.getElementById('settingsModal');if(m&&!m.classList.contains('hidden')){var x=document.getElementById('closeSettings');if(x)x.click();return true;}if(typeof remoteBack==='function'){remoteBack();return true;}}catch(e){}return false;})()") { [weak self] handled in
            if handled as? Bool != true, let web = self?.webView, web.canGoBack { web.goBack() }
        }
    }
}
struct TVChannel: Codable, Identifiable {
    let id: String
    let name: String
}

struct ContentView: View {
    @StateObject private var browser = AstonBrowser()
    private let dark = Color(red: 0.06, green: 0.08, blue: 0.12)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.back() } label: { Image(systemName: "chevron.left") }
                Text("ASTON TV PREMIUM").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 6)
                Button { browser.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { browser.showServers = true } label: { Image(systemName: "gearshape") }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 17)
            .frame(height: 48)
            .background(Color(red: 0.12, green: 0.15, blue: 0.21))
            ZStack {
                AstonWebView(browser: browser)
                if browser.isLoading { ProgressView().tint(.white) }
                if let message = browser.error {
                    VStack(spacing: 18) {
                        Image(systemName: "wifi.slash").font(.largeTitle)
                        Text("Няма връзка с Aston TV").font(.headline)
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                        Button("Обнови") { browser.webView?.reload() }.buttonStyle(.borderedProminent)
                        Button("Смени сървъра") { browser.showServers = true }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(dark)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    control("chevron.left.2", "Канал −") { browser.channel(-1) }
                    control("chevron.right.2", "Канал +") { browser.channel(1) }
                    control("list.bullet", "Канали") { browser.loadChannelList() }
                    control("gobackward.10", "−10 сек") { browser.seek(-10) }
                    control("goforward.10", "+10 сек") { browser.seek(10) }
                    control("playpause", "Пауза") { browser.playPause() }
                    control("list.bullet.rectangle", "EPG") { browser.open("guide") }
                    control("web.camera", "Камери") { browser.open("cameras") }
                    control("arrow.up.left.and.arrow.down.right", "Цял екран") { browser.fullScreen() }
                }.padding(.horizontal, 8).padding(.vertical, 6)
            }.background(Color(red: 0.12, green: 0.15, blue: 0.21))
        }
        .foregroundColor(.white)
        .background(dark)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $browser.showServers) {
            NavigationStack {
                List {
                    Button("Домашен Premium 4.0") {
                        browser.load(AstonBrowser.local); browser.showServers = false
                    }
                    Button("Външен Aston TV") {
                        browser.load(AstonBrowser.remote); browser.showServers = false
                    }
                    Text("Локалният сървър изисква домашна Wi-Fi мрежа или VPN. Външният домейн може да обслужва Gateway 3.x.")
                        .font(.caption)
                }
                .navigationTitle("Сървър")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { browser.showServers = false }
                }}
            }
        }
        .sheet(isPresented: $browser.showChannels) {
            NavigationStack {
                List(browser.channelItems) { channel in
                    Button(channel.name) { browser.select(channel) }
                }
                .navigationTitle("Телевизионни канали")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { browser.showChannels = false }
                }}
            }
        }
    }
    private func control(_ system: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.system(size: 18))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }.frame(minWidth: 61, minHeight: 46)
                .padding(.horizontal, 4)
                .background(Color(red: 0.18, green: 0.23, blue: 0.31), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}
private struct AstonWebView: UIViewRepresentable {
    @ObservedObject var browser: AstonBrowser
    func makeCoordinator() -> Coordinator { Coordinator(browser) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        browser.webView = view
        view.load(URLRequest(url: browser.url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let browser: AstonBrowser
        init(_ browser: AstonBrowser) { self.browser = browser }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let local = url.scheme == "http" && url.host == "10.10.10.179" && url.port == 8424
            let remote = url.scheme == "https" && url.host == "tv.astonserver.eu"
            decisionHandler(local || remote || url.scheme == "about" || url.scheme == "blob" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser.error = nil; browser.isLoading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.isLoading = false
            browser.isExternal = webView.url?.host == "tv.astonserver.eu"
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            browser.error = error.localizedDescription
            browser.isLoading = false
        }
    }
}
