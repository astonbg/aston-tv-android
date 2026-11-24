import SwiftUI
import AVFoundation

@main
struct AstonTVApp: App {
    init() {
        // звукът върви и при включен безшумен режим и при заключен екран (музикалните канали)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    var body: some Scene {
        WindowGroup {
            AstonWebView()
                .background(Color(red: 7/255, green: 7/255, blue: 10/255))
                .ignoresSafeArea(edges: .bottom)
                .preferredColorScheme(.dark)
        }
    }
}
