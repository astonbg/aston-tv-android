import SwiftUI
import AVFoundation
import WebKit

/// Скенер за QR кода, който телевизорът показва при сдвояване.
struct ScannerScreen: View {
    @EnvironmentObject var app: AppState
    @State private var denied = false
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if denied {
                VStack(spacing: 14) {
                    Text("Няма достъп до камерата").font(.title3).bold()
                    Text("Разреши камерата: Настройки → Aston TV → Камера").multilineTextAlignment(.center).opacity(0.8)
                    Button("Отвори Настройки") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                }.foregroundColor(.white).padding(40).frame(maxHeight: .infinity)
            } else {
                QRCameraView { text in app.scanned(text) }.ignoresSafeArea()
                RoundedRectangle(cornerRadius: 24).stroke(Color(red: 1, green: 0.18, blue: 0.24), lineWidth: 4)
                    .frame(width: 250, height: 250).frame(maxHeight: .infinity)
            }
            HStack {
                Text("Насочи към QR кода на екрана").foregroundColor(.white).font(.headline)
                Spacer()
                Button(action: { app.showScanner = false }) {
                    Text("Затвори").bold().padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color(red: 1, green: 0.18, blue: 0.24)).foregroundColor(.white).cornerRadius(18)
                }
            }.padding()
        }
        .onAppear {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted: denied = true
            case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { denied = !ok } }
            default: break
            }
        }
    }
}

struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> QRCameraController { let c = QRCameraController(); c.onCode = onCode; return c }
    func updateUIViewController(_ vc: QRCameraController, context: Context) {}
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        view.layer.addSublayer(p)
        preview = p
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if session.isRunning { session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let o = objects.first as? AVMetadataMachineReadableCodeObject, let s = o.stringValue else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        session.stopRunning()
        onCode?(s)
    }
}

/// Aston Studio вътре в приложението (администрация: устройства, камери, канали, на живо).
struct StudioScreen: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { app.showStudio = false }) {
                    Text("‹ Aston TV").bold().foregroundColor(.white)
                }
                Spacer()
                Text("Aston Studio").font(.headline).foregroundColor(.white)
                Spacer()
                Text("‹ Aston TV").bold().opacity(0)
            }.padding(.horizontal).padding(.vertical, 10).background(Color(red: 0.08, green: 0.08, blue: 0.1))
            StudioWebView()
        }.background(Color.black.ignoresSafeArea())
    }
}

struct StudioWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()   // помни входа в Studio
        let v = WKWebView(frame: .zero, configuration: c)
        v.isOpaque = false
        v.backgroundColor = .black
        v.allowsBackForwardNavigationGestures = true
        v.load(URLRequest(url: URL(string: "https://studio.astonserver.eu/")!))
        return v
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
