import SwiftUI
import AVFoundation

@main
struct AstonTVApp: App {
    init() {
        // звукът върви и при безшумен режим и при заключен екран (музикалните канали)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
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
    }
}
