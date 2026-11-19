import AppKit
import WebKit

// Real WebKit regression: the Gateway-style player stays private in an IIFE,
// and its channel buttons arrive after didFinish. This is NOT a live-stream test.
final class TestDelegate:NSObject,WKNavigationDelegate {
    let script:String
    init(script:String){self.script=script}
    func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {
        web.evaluateJavaScript(script) { value,error in
            guard error == nil,value as? Bool == true else {print("FAIL: bridge JavaScript");exit(1)}
            DispatchQueue.main.asyncAfter(deadline:.now()+1.5) {
                web.evaluateJavaScript("({selected:window.selectedChannel,privatePlayer:typeof playback,visible:getComputedStyle(document.getElementById('video')).visibility})") { value,error in
                    guard error == nil,let result=value as? [String:Any],
                          result["selected"] as? String == "id:C501",
                          result["privatePlayer"] as? String == "undefined",
                          result["visible"] as? String == "visible" else {print("FAIL: DOM selection or visibility");exit(1)}
                    print("PASS: real WKWebView selects delayed channel through private Gateway handler; video visible with strict style CSP")
                    exit(0)
                }
            }
        }
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let script=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
    .replacingOccurrences(of:"__ASTON_REQUEST__",with:"{\"channel\":\"id:C501\",\"requestId\":\"test\"}")
let delegate=TestDelegate(script:script)
let web=WKWebView(frame:NSRect(x:0,y:0,width:440,height:250))
web.navigationDelegate=delegate
let window=NSWindow(contentRect:web.frame,styleMask:[.borderless],backing:.buffered,defer:false)
window.contentView=web
web.loadHTMLString("""
<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'unsafe-inline'; style-src 'self'">
<div id="authView" class="hidden"></div><div id="channelRail"></div><div id="status"></div><video id="video"></video>
<script>(function(){function playback(id){window.selectedChannel=id;}
document.getElementById('channelRail').onclick=function(e){playback(e.target.getAttribute('data-id'));};
setTimeout(function(){var b=document.createElement('button');b.setAttribute('data-id','id:C501');document.getElementById('channelRail').appendChild(b);},600);})();</script>
""",baseURL:URL(string:"https://gateway.test/"))
DispatchQueue.main.asyncAfter(deadline:.now()+30){print("FAIL: WKWebView test timed out");exit(1)}
app.run()
