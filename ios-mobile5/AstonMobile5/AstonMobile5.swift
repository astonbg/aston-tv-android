import SwiftUI
import AVKit
import Combine

private enum TVStyle {
    static let bg = Color(red: 0.04, green: 0.055, blue: 0.085)
    static let panel = Color(red: 0.11, green: 0.14, blue: 0.19)
    static let teal = Color(red: 0.24, green: 0.80, blue: 0.91)
    static let muted = Color(red: 0.58, green: 0.65, blue: 0.74)
}
struct TVChannel: Identifiable {
    let id, name, number, group, logo, now, next: String
    init(_ obj: [String: Any]) {
        func val(_ v: Any?) -> String {
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return ""
        }
        id = val(obj["id"])
        name = val(obj["name"])
        number = val(obj["number"])
        group = val(obj["group"])
        logo = val(obj["logo_url"])
        now = val((obj["now"] as? [String:Any])?["title"])
        next = val((obj["next"] as? [String:Any])?["title"])
    }
}
struct TVCamera: Identifiable {
    let id, name: String
    let enabled: Bool
    init(_ obj: [String:Any]) {
        id = obj["id"] as? String ?? ""
        name = obj["name"] as? String ?? "Камера"
        enabled = obj["enabled"] as? Bool ?? false
    }
}
enum TVSection: Int, CaseIterable {
    case channels, favorites, cameras, media
    var name: String {
        switch self {
        case .channels:return "Телевизия"
        case .favorites:return "Любими"
        case .cameras:return "Камери"
        case .media:return "Медия"
        }
    }
    var icon: String {
        switch self {
        case .channels:return "tv"
        case .favorites:return "star.fill"
        case .cameras:return "video.fill"
        case .media:return "film.stack"
        }
    }
}
@MainActor
final class TVEngine: ObservableObject {
    static let local = URL(string:"http://10.10.10.179:8424/")!
    static let remote = URL(string:"https://tv.astonserver.eu/")!
    @Published var channels: [TVChannel] = []
    @Published var cameras: [TVCamera] = []
    @Published var selected: TVChannel?
    @Published var selectedCamera: TVCamera?
    @Published var section: TVSection = .channels
    @Published var searching = ""
    @Published var code = ""
    @Published var showPair = false
    @Published var paired = false
    @Published var loading = false
    @Published var isPlaying = false
    @Published var status = "Свързване..."
    @Published var errorText: String?
    @Published var showSettings = false
    @Published var showList = false
    @Published var showEPG = false
    @Published var showFullscreen = false
    @Published var hasSeek = false
    @Published var favorites = Set(UserDefaults.standard.stringArray(forKey:"aston.mobile5.favs") ?? [])
    let player = AVPlayer()
    private var refresh: Task<Void,Never>?
    private var sequence = 0
    private var progressObserver: Any?
    private let session: URLSession
    var server: URL {
        UserDefaults.standard.string(forKey:"aston.mobile5.server") == Self.remote.absoluteString ? Self.remote : Self.local
    }
    init() {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpShouldSetCookies = true
        session = URLSession(configuration:c)
        progressObserver = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:1,preferredTimescale:600),queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let range = self.player.currentItem?.seekableTimeRanges.last?.timeRangeValue {
                    self.hasSeek = CMTimeGetSeconds(range.duration) > 2
                } else { self.hasSeek = false }
            }
        }
    }
    deinit {
        if let obs=progressObserver {player.removeTimeObserver(obs)}
    }
    private func query(_ path: String, post: [String:Any]? = nil) async throws -> [String:Any] {
        var req = URLRequest(url:server.appendingPathComponent(path),timeoutInterval:20)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let post {
            req.httpMethod = "POST"
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject:post)
        }
        let (data,response) = try await session.data(for:req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {throw NSError(domain:"Aston TV",code:401,userInfo:[NSLocalizedDescriptionKey:"Изисква се сдвояване"])}
        if !(200..<300).contains(status) {
            let body = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            throw NSError(domain:"Aston TV",code:status,userInfo:[NSLocalizedDescriptionKey:(body?["error"] as? String) ?? "Грешка от сървъра: \(status)"])
        }
        return (try JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    }
    func connect() async {
        loading=true
        defer{loading=false}
        do {
            _ = try await query("api/public/me")
            paired=true;showPair=false
            await reload()
            if selected == nil, let last=UserDefaults.standard.string(forKey:"aston.mobile5.last") {
                selected=channels.first{$0.id==last}
            }
            status="Готово · \(channels.count) канала"
        } catch let e as NSError where e.code == 401 {
            paired=false;showPair=true;status="Въведи 8-цифрен код"
        } catch {
            status="Няма връзка"
            errorText=error.localizedDescription
        }
    }
    func pair() async {
        guard code.count == 8 && code.allSatisfy(\.isNumber) else {
            errorText="Кодът трябва да съдържа 8 цифри";return
        }
        loading=true
        defer{loading=false}
        do {
            _ = try await query("api/public/pair",post:["code":code])
            code=""
            await connect()
        } catch {errorText=error.localizedDescription}
    }
    func reload() async {
        do {
            let r = try await query("api/public/channels")
            channels=((r["channels"] as? [[String:Any]]) ?? []).map(TVChannel.init)
            if let old=selected { selected=channels.first{$0.id==old.id} }
        } catch {errorText=error.localizedDescription}
        do {
            let r=try await query("api/public/cameras")
            cameras=((r["cameras"] as? [[String:Any]]) ?? []).map(TVCamera.init)
        } catch {}
    }
    func changeServer(_ u:URL) {
        stop()
        paired=false;channels=[];cameras=[]
        UserDefaults.standard.set(u.absoluteString,forKey:"aston.mobile5.server")
        Task {await connect()}
    }
    private func playURL(_ payload:[String:Any]) throws {
        guard let s=payload["url"] as? String,
              let u=URL(string:s,relativeTo:server)?.absoluteURL,
              (u.scheme == "https" || (u.scheme == "http" && u.host == "10.10.10.179")) else {
            throw NSError(domain:"Aston TV",code:1,userInfo:[NSLocalizedDescriptionKey:"Невалиден видео адрес"])
        }
        player.replaceCurrentItem(with:AVPlayerItem(url:u))
        player.play()
        isPlaying=true
    }
    func play(_ ch:TVChannel) async {
        sequence += 1
        let current=sequence
        refresh?.cancel()
        loading=true
        selected=ch;selectedCamera=nil;section = .channels
        status="Зареждане на \(ch.name)"
        UserDefaults.standard.set(ch.id,forKey:"aston.mobile5.last")
        defer {if current==sequence{loading=false}}
        do {
            let r=try await query("api/public/play",post:["channel_id":ch.id,"format":"auto"])
            guard current==sequence else{return}
            if (r["format"] as? String)=="mpegts" {
                status="Този канал изисква HLS за iPhone"
                player.replaceCurrentItem(with:nil);isPlaying=false
                return
            }
            try playURL(r)
            status="НА ЖИВО"
            refreshLink(channel:ch.id,camera:nil)
        } catch {if current==sequence{status="Грешка";errorText=error.localizedDescription}}
    }
    func playCamera(_ cam:TVCamera) async {
        guard cam.enabled else{return}
        sequence += 1
        let current=sequence
        refresh?.cancel()
        loading=true
        selectedCamera=cam;selected=nil;section = .cameras
        status="Свързване с \(cam.name)"
        defer {if current==sequence{loading=false}}
        do {
            let r=try await query("api/public/camera-play",post:["camera":cam.id,"format":"hls"])
            guard current==sequence else{return}
            try playURL(r)
            status="КАМЕРА · LIVE"
            refreshLink(channel:nil,camera:cam.id)
        } catch {if current==sequence{status="Камерата не е достъпна";errorText=error.localizedDescription}}
    }
    private func refreshLink(channel:String?,camera:String?) {
        let captured=sequence
        refresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds:23*60*1_000_000_000)
            guard let self, !Task.isCancelled, self.sequence==captured else{return}
            if let channel,let item=self.channels.first(where:{$0.id==channel}) {await self.play(item)}
            else if let camera,let item=self.cameras.first(where:{$0.id==camera}) {await self.playCamera(item)}
        }
    }
    func step(_ n:Int) {
        guard !channels.isEmpty else{return}
        let idx=channels.firstIndex(where:{$0.id==selected?.id}) ?? (n>0 ? -1 : 0)
        let next=(idx+n+channels.count)%channels.count
        Task {await play(channels[next])}
    }
    func pause() {
        if isPlaying {player.pause()}else{player.play()}
        isPlaying.toggle()
    }
    func seek(_ secs:Double) {
        guard hasSeek,let r=player.currentItem?.seekableTimeRanges.last?.timeRangeValue else{return}
        let a=CMTimeGetSeconds(r.start), b=CMTimeGetSeconds(CMTimeRangeGetEnd(r))
        let cur=CMTimeGetSeconds(player.currentTime())
        guard a.isFinite && b.isFinite && cur.isFinite else{return}
        player.seek(to:CMTime(seconds:min(b,max(a,cur+secs)),preferredTimescale:600))
    }
    func stop() {
        sequence += 1;refresh?.cancel()
        player.pause();player.replaceCurrentItem(with:nil)
        isPlaying=false;hasSeek=false;selected=nil;selectedCamera=nil
        status="Избери канал"
    }
    func favorite(_ ch:TVChannel) {
        if favorites.contains(ch.id) {favorites.remove(ch.id)}else{favorites.insert(ch.id)}
        UserDefaults.standard.set(Array(favorites),forKey:"aston.mobile5.favs")
    }
    var title:String {selected?.name ?? selectedCamera?.name ?? "Избери канал"}
    var now:String {selected?.now ?? ""}
    var next:String {selected?.next ?? ""}
    func logoURL(_ ch:TVChannel)->URL? {
        guard ch.logo.hasPrefix("/api/public/logo/")else{return nil}
        return URL(string:ch.logo,relativeTo:server)?.absoluteURL
    }
    func thumbURL(_ cam:TVCamera)->URL {server.appendingPathComponent("api/public/thumb/\(cam.id)")}
}
struct NativePlayerView:UIViewControllerRepresentable {
    let player:AVPlayer
    var controls=false
    func makeUIViewController(context:Context)->AVPlayerViewController {
        let vc=AVPlayerViewController()
        vc.player=player;vc.showsPlaybackControls=controls;vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback=true
        return vc
    }
    func updateUIViewController(_ vc:AVPlayerViewController,context:Context) {
        if vc.player !== player {vc.player=player}
        vc.showsPlaybackControls=controls
    }
}
struct RemoteImage:View {
    let url:URL
    @State private var picture:UIImage?
    var body:some View {
        Group {
            if let picture {Image(uiImage:picture).resizable().scaledToFit()}
            else {Image(systemName:"tv").foregroundStyle(TVStyle.muted)}
        }
        .task(id:url) {
            if let result=try? await URLSession.shared.data(from:url),
               (result.1 as? HTTPURLResponse)?.statusCode==200,
               let i=UIImage(data:result.0) {picture=i}
        }
    }
}
@main
struct AstonMobile5App:App {
    var body:some Scene {WindowGroup{MobilePlayerHome()}}
}
struct MobilePlayerHome:View {
    @StateObject private var tv=TVEngine()
    @State private var category="Всички"
    @State private var showFull=false
    private var filtered:[TVChannel] {
        tv.channels.filter{c in
            let s="\(c.name) \(c.group) \(c.now)".lowercased()
            if !tv.searching.isEmpty && !s.localizedCaseInsensitiveContains(tv.searching){return false}
            if category=="Филми"{return ["film","movie","филм","кино","action","comedy","horror"].contains(where:s.contains)}
            if category=="Сериали"{return ["series","сериал","shows"].contains(where:s.contains)}
            if category=="Музика"{return ["music","муз","house","chalga","чалга","mix"].contains(where:s.contains)}
            return true
        }
    }
    var body:some View {
        ZStack {
            TVStyle.bg.ignoresSafeArea()
            VStack(spacing:0) {
                topBar
                playerArea
                Group {
                    switch tv.section {
                    case .channels: channelList
                    case .favorites: favoritesList
                    case .cameras: camerasList
                    case .media: mediaList
                    }
                }
                bottomBar
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {await tv.connect()}
        .sheet(isPresented:$tv.showList){channelSheet}
        .sheet(isPresented:$tv.showEPG){guideSheet}
        .sheet(isPresented:$tv.showSettings){settingsSheet}
        .sheet(isPresented:$tv.showPair){pairSheet}
        .fullScreenCover(isPresented:$showFull) {
            ZStack(alignment:.topTrailing) {
                Color.black.ignoresSafeArea()
                NativePlayerView(player:tv.player,controls:true).ignoresSafeArea()
                Button {showFull=false} label: {Image(systemName:"xmark").font(.headline).padding(13).background(.black.opacity(0.7),in:Circle())}
                    .padding(18)
            }
        }
        .alert("Aston TV",isPresented:Binding(get:{tv.errorText != nil},set:{if !$0{tv.errorText=nil}})) {
            Button("OK",role:.cancel){tv.errorText=nil}
        } message: {Text(tv.errorText ?? "")}
    }
    private var topBar:some View {
        HStack(spacing:11) {
            Image(systemName:"play.rectangle.fill").font(.system(size:27)).foregroundStyle(TVStyle.teal)
            VStack(alignment:.leading,spacing:0) {
                Text("ASTON").font(.system(size:18,weight:.black,design:.rounded)).tracking(2)
                Text("TV MOBILE").font(.system(size:9,weight:.bold)).foregroundStyle(TVStyle.teal).tracking(2)
            }
            Spacer()
            Text("● LIVE").font(.system(size:11,weight:.bold)).foregroundStyle(TVStyle.teal)
                .padding(.horizontal,10).padding(.vertical,7).background(TVStyle.panel,in:Capsule())
            Button {Task{await tv.reload()}} label:{Image(systemName:"arrow.clockwise").frame(width:33,height:36)}
            Button {tv.showSettings=true} label:{Image(systemName:"gearshape.fill").frame(width:33,height:36)}
        }.padding(.horizontal,15).padding(.vertical,8)
    }
    private var playerArea:some View {
        VStack(spacing:0) {
            ZStack {
                Color.black
                NativePlayerView(player:tv.player).opacity(tv.selected != nil || tv.selectedCamera != nil ? 1 : 0)
                if tv.selected == nil && tv.selectedCamera == nil {
                    VStack(spacing:12) {
                        Image(systemName:"tv.and.hifispeaker.fill").font(.system(size:41)).foregroundStyle(TVStyle.teal)
                        Text("ИЗБЕРИ ТЕЛЕВИЗИОНЕН КАНАЛ").font(.system(size:11,weight:.semibold))
                        Text("Плъзни за смяна на канали").font(.system(size:11)).foregroundStyle(TVStyle.muted)
                    }
                }
                if tv.loading {Color.black.opacity(0.28); ProgressView().tint(TVStyle.teal).controlSize(.large)}
                VStack {
                    HStack {
                        Text(tv.status).font(.system(size:10,weight:.semibold)).lineLimit(1)
                            .padding(7).background(.black.opacity(0.7),in:Capsule())
                        Spacer()
                        Button {showFull=true} label:{Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:16)).padding(8).background(.black.opacity(0.7),in:Circle())}
                    }
                    Spacer()
                    HStack {
                        Button {tv.step(-1)} label:{Image(systemName:"chevron.left").font(.title2.bold()).frame(width:48,height:55).background(.black.opacity(0.5),in:RoundedRectangle(cornerRadius:12))}
                        Spacer()
                        Button {tv.pause()} label:{Image(systemName:tv.isPlaying ? "pause.fill":"play.fill").font(.title).frame(width:62,height:62).background(.black.opacity(0.5),in:Circle())}
                        Spacer()
                        Button {tv.step(1)} label:{Image(systemName:"chevron.right").font(.title2.bold()).frame(width:48,height:55).background(.black.opacity(0.5),in:RoundedRectangle(cornerRadius:12))}
                    }
                }.padding(13)
            }
            .aspectRatio(16/9,contentMode:.fit)
            .gesture(DragGesture(minimumDistance:55).onEnded{g in
                if abs(g.translation.height)>abs(g.translation.width) {tv.step(g.translation.height<0 ? 1 : -1)}
                else if abs(g.translation.width)>85 {tv.seek(g.translation.width<0 ? 10 : -10)}
            })
            VStack(spacing:10) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(tv.title).font(.system(size:17,weight:.bold)).lineLimit(1)
                        Text(tv.now.isEmpty ? tv.status : "СЕГА · \(tv.now)").font(.system(size:11)).foregroundStyle(TVStyle.muted).lineLimit(1)
                    }
                    Spacer()
                    if let ch=tv.selected {
                        Button {tv.favorite(ch)} label:{Image(systemName:tv.favorites.contains(ch.id) ? "star.fill":"star")
                            .foregroundStyle(tv.favorites.contains(ch.id) ? .yellow:.white).frame(width:38,height:38)}
                    }
                    Button {tv.showEPG=true} label:{Image(systemName:"list.bullet.rectangle").frame(width:38,height:38)}
                }
                HStack(spacing:0) {
                    control("gobackward.10","−10 сек",allowed:tv.hasSeek){tv.seek(-10)}
                    control("list.bullet","Канали"){tv.showList=true}
                    control("goforward.10","+10 сек",allowed:tv.hasSeek){tv.seek(10)}
                    control("stop.fill","Стоп"){tv.stop()}
                }
            }.padding(12).background(TVStyle.panel)
        }
    }
    private func control(_ icon:String,_ title:String,allowed:Bool=true,action:@escaping ()->Void)->some View {
        Button(action:action) {
            VStack(spacing:6){Image(systemName:icon).font(.system(size:19,weight:.semibold));Text(title).font(.system(size:10,weight:.medium))}
                .foregroundStyle(allowed ? Color.white:TVStyle.muted.opacity(0.4))
                .frame(maxWidth:.infinity).frame(height:43)
        }.buttonStyle(.plain).disabled(!allowed)
    }
    private var channelList:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:13) {
                HStack {
                    Text("ТВ канали").font(.system(size:21,weight:.bold))
                    Spacer()
                    Text("\(tv.channels.count) КАНАЛА").font(.system(size:11,weight:.semibold)).foregroundStyle(TVStyle.muted)
                }
                HStack {
                    Image(systemName:"magnifyingglass").foregroundStyle(TVStyle.muted)
                    TextField("Търси канал или предаване",text:$tv.searching).font(.system(size:14)).autocorrectionDisabled()
                }.padding(12).background(TVStyle.panel,in:RoundedRectangle(cornerRadius:12))
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(["Всички","Филми","Сериали","Музика"],id:\.self){c in
                            Button {category=c} label:{Text(c).font(.system(size:12,weight:.semibold))
                                .padding(.horizontal,15).padding(.vertical,9)
                                .background(category==c ? TVStyle.teal:TVStyle.panel,in:Capsule())
                                .foregroundStyle(category==c ? TVStyle.bg:Color.white)}
                        }
                    }
                }
                LazyVStack(spacing:8) {ForEach(filtered){channelRow($0)}}
                if tv.channels.isEmpty {Text("Няма канали. Провери връзката с Aston TV Gateway.").foregroundStyle(TVStyle.muted)}
            }.padding(15)
        }.scrollDismissesKeyboard(.interactively)
    }
    private var favoritesList:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text("Любими канали").font(.title2.bold())
                Text("Запази каналите за смяна с едно докосване").font(.caption).foregroundStyle(TVStyle.muted)
                ForEach(tv.channels.filter{tv.favorites.contains($0.id)}){channelRow($0)}
                if tv.favorites.isEmpty {Text("Избери ☆ до канала, за да го добавиш.").foregroundStyle(TVStyle.muted).padding(20)}
            }.padding(15)
        }
    }
    private var camerasList:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:13) {
                Text("Камери").font(.title2.bold())
                Text("Dahua · докосни за видео на живо").font(.caption).foregroundStyle(TVStyle.muted)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:11) {
                    ForEach(tv.cameras){cam in
                        Button {Task{await tv.playCamera(cam)}} label:{
                            VStack(alignment:.leading,spacing:7) {
                                ZStack {
                                    RoundedRectangle(cornerRadius:9).fill(Color.black)
                                    RemoteImage(url:tv.thumbURL(cam)).aspectRatio(16/9,contentMode:.fit)
                                    VStack{HStack{Spacer();Circle().fill(cam.enabled ? Color.green:Color.gray).frame(width:7,height:7).padding(8)};Spacer()}
                                }.aspectRatio(16/9,contentMode:.fit)
                                Text(cam.name).font(.system(size:13,weight:.semibold))
                                Text(cam.enabled ? "НА ЛИНИЯ":"ИЗКЛЮЧЕНА").font(.system(size:10)).foregroundStyle(TVStyle.muted)
                            }.padding(9).background(TVStyle.panel,in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain).disabled(!cam.enabled)
                    }
                }
                if tv.cameras.isEmpty {Text("Няма достъпни камери.").foregroundStyle(TVStyle.muted)}
            }.padding(15)
        }
    }
    private var mediaList:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:13) {
                Text("Медия и музика").font(.title2.bold())
                Text("Филми, сериали и музикални канали от Aston TV").font(.caption).foregroundStyle(TVStyle.muted)
                ForEach(tv.channels.filter {ch in
                    let s="\(ch.name) \(ch.group)".lowercased()
                    return ["film","movie","филм","кино","series","сериал","music","муз","house","chalga","чалга"].contains(where:s.contains)
                }){channelRow($0)}
                Text("Plex VOD каталогът изисква отделна интеграция с API; тук са наличните телевизионни медийни канали.")
                    .font(.caption).foregroundStyle(TVStyle.muted).padding(.vertical,10)
            }.padding(15)
        }
    }
    private func channelRow(_ ch:TVChannel)->some View {
        HStack(spacing:8) {
            Button {Task{await tv.play(ch)}} label:{
                HStack(spacing:10) {
                    ZStack {
                        RoundedRectangle(cornerRadius:10).fill(Color.black).frame(width:71,height:56)
                        if let url=tv.logoURL(ch) {RemoteImage(url:url).frame(width:67,height:52)}
                        else {Text(ch.number.isEmpty ? "TV":ch.number).font(.headline).foregroundStyle(TVStyle.teal)}
                    }
                    VStack(alignment:.leading,spacing:4) {
                        Text((ch.number.isEmpty ? "" : "\(ch.number) · ")+ch.name).font(.system(size:14,weight:.semibold)).lineLimit(1)
                        Text(ch.now.isEmpty ? ch.group : "СЕГА  \(ch.now)").font(.system(size:11)).foregroundStyle(TVStyle.muted).lineLimit(1)
                        if !ch.next.isEmpty {Text("СЛЕДВА  \(ch.next)").font(.system(size:10)).foregroundStyle(TVStyle.teal).lineLimit(1)}
                    }
                    Spacer(minLength:0)
                    if tv.selected?.id==ch.id{Image(systemName:"waveform").foregroundStyle(TVStyle.teal)}
                }
            }.buttonStyle(.plain)
            Button{tv.favorite(ch)}label:{Image(systemName:tv.favorites.contains(ch.id) ? "star.fill":"star")
                .foregroundStyle(tv.favorites.contains(ch.id) ? Color.yellow:TVStyle.muted).frame(width:36,height:52)}
        }.padding(9).background(TVStyle.panel,in:RoundedRectangle(cornerRadius:12))
    }
    private var bottomBar:some View {
        HStack(spacing:0) {
            ForEach(TVSection.allCases,id:\.rawValue){item in
                Button {tv.section=item}label:{
                    VStack(spacing:5) {Image(systemName:item.icon).font(.system(size:18));Text(item.name).font(.system(size:10,weight:.semibold))}
                        .foregroundStyle(tv.section==item ? TVStyle.teal:TVStyle.muted)
                        .frame(maxWidth:.infinity).frame(height:54)
                }
            }
        }.padding(.top,5).background(TVStyle.panel)
    }
    private var pairSheet:some View {
        VStack(spacing:18) {
            Spacer()
            Image(systemName:"link.circle.fill").font(.system(size:58)).foregroundStyle(TVStyle.teal)
            Text("Свържи Aston TV").font(.system(size:27,weight:.bold))
            Text("Въведи 8-цифрения код от Aston TV Core").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(TVStyle.muted)
            TextField("00000000",text:$tv.code).keyboardType(.numberPad)
                .font(.system(size:27,weight:.bold,design:.monospaced)).multilineTextAlignment(.center)
                .padding(18).background(TVStyle.panel,in:RoundedRectangle(cornerRadius:12))
                .onChange(of:tv.code){value in tv.code=String(value.filter(\.isNumber).prefix(8))}
            Button {Task{await tv.pair()}}label:{Text("Сдвояване").frame(maxWidth:.infinity).padding(15).fontWeight(.bold)}
                .background(TVStyle.teal,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(TVStyle.bg)
                .disabled(tv.code.count != 8 || tv.loading)
            Button("Смени сървъра"){tv.showPair=false;tv.showSettings=true}.foregroundStyle(TVStyle.teal)
            Spacer()
        }.padding(25).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(TVStyle.bg).interactiveDismissDisabled()
    }
    private var guideSheet:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:17) {
                    Text(tv.title).font(.title2.bold())
                    guideCard("СЕГА",tv.now.isEmpty ? "Няма текуща програма":tv.now)
                    guideCard("СЛЕДВА",tv.next.isEmpty ? "Няма следваща програма":tv.next)
                    Text("Данните идват от Aston TV Gateway").font(.caption).foregroundStyle(.secondary)
                }.padding(17)
            }
            .navigationTitle("ТВ програма")
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Затвори"){tv.showEPG=false}}}
        }.preferredColorScheme(.dark)
    }
    private func guideCard(_ k:String,_ name:String)->some View {
        VStack(alignment:.leading,spacing:10){Text(k).font(.caption.bold()).foregroundStyle(TVStyle.teal);Text(name).font(.body.weight(.medium))}
            .frame(maxWidth:.infinity,alignment:.leading).padding(16).background(TVStyle.panel,in:RoundedRectangle(cornerRadius:12))
    }
    private var channelSheet:some View {
        NavigationStack {
            List(tv.channels){ch in
                Button {tv.showList=false;Task{await tv.play(ch)}}label:{
                    VStack(alignment:.leading,spacing:4){
                        Text((ch.number.isEmpty ? "" : "\(ch.number) · ")+ch.name).fontWeight(.semibold)
                        if !ch.now.isEmpty{Text("Сега: \(ch.now)").font(.caption).foregroundStyle(.secondary)}
                    }
                }
            }.navigationTitle("Избор на канал")
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){tv.showList=false}}}
        }.preferredColorScheme(.dark)
    }
    private var settingsSheet:some View {
        NavigationStack {
            List {
                Button("Домашен сървър · 10.10.10.179:8424"){tv.showSettings=false;tv.changeServer(TVEngine.local)}
                Button("Външен портал · tv.astonserver.eu"){tv.showSettings=false;tv.changeServer(TVEngine.remote)}
                Text("Външният адрес може да е със стара версия на Gateway. Локалният изисква домашна Wi-Fi мрежа или VPN.")
                    .font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Сървър")
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){tv.showSettings=false}}}
        }.preferredColorScheme(.dark)
    }
}
