import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// MARK: - Brand

enum HB {
    static let navy = Color(red: 20/255, green: 40/255, blue: 90/255)       // #14285A
    static let midnight = Color(red: 15/255, green: 30/255, blue: 69/255)   // #0F1E45 icon navy
    static let pink = Color(red: 242/255, green: 184/255, blue: 198/255)    // #F2B8C6
    static let red = Color(red: 155/255, green: 27/255, blue: 31/255)       // #9B1B1F
    static let silver = Color(red: 200/255, green: 202/255, blue: 206/255)  // #C8CACE
    static let group = "group.com.hiello.family"
}

/// The heart from the Hiello logo (the one that dots the i), drawn from the same path as the app.
struct LogoHeart: Shape {
    func path(in r: CGRect) -> Path {
        // SVG: M0 -5 C-3 -12 -14 -10 -12 -1 C-11 4 -4 8 0 12 C4 8 11 4 12 -1 C14 -10 3 -12 0 -5Z  (box -15...15, -14...14)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + (x + 15) / 30 * r.width, y: r.minY + (y + 14) / 28 * r.height)
        }
        var path = Path()
        path.move(to: p(0, -5))
        path.addCurve(to: p(-12, -1), control1: p(-3, -12), control2: p(-14, -10))
        path.addCurve(to: p(0, 12), control1: p(-11, 4), control2: p(-4, 8))
        path.addCurve(to: p(12, -1), control1: p(4, 8), control2: p(11, 4))
        path.addCurve(to: p(0, -5), control1: p(14, -10), control2: p(3, -12))
        path.closeSubpath()
        return path
    }
}

struct HeartBadge: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            LogoHeart().fill(HB.pink)
            LogoHeart().stroke(HB.red, style: StrokeStyle(lineWidth: max(1.5, size / 12), lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - What the app shares with the widget

struct HConfig: Decodable {
    var url: String?
    var key: String?
    var fid: String?
    var sec: String?
    var mid: String?
    var role: String?
    var me: String?
    var gp: String?
    var people: [String]?
    var demo: Bool?
    var items: [HLocalItem]?
    var err: String?
}

struct HLocalItem: Decodable {
    var id: String
    var from: String
    var note: String
    var at: Double
    var watched: Bool
    var hearts: Int
    var file: String
    var video: Bool?
    var flip: Bool?
    var mine: Bool?     // you sent it (your own hi's don't show on your widget)
}

struct HRow: Decodable {
    var id: String
    var member_id: String?
    var from_name: String?
    var note: String?
    var created_at: String?
    var watched_at: String?
    var hearts: Int?
    var thumb_path: String?
    var media_kind: String?
    var shown_at: String?   // put back on everyone's widget by its sender
}

struct HFeed: Decodable {
    var gp_name: String?
    var posts: [HRow]?
    var replies: [HRow]?
}

enum HStore {
    static var defaults: UserDefaults? { UserDefaults(suiteName: HB.group) }
    static var dir: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HB.group) }

    static func config() -> HConfig? {
        guard let s = defaults?.string(forKey: "hiello.config"), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HConfig.self, from: d)
    }

    /// Hearts sent from the widget that the server may not have counted yet, so the count goes up right away.
    static func pendingHearts(_ id: String) -> Int { defaults?.integer(forKey: "hiello.heart." + id) ?? 0 }
    static func addPendingHeart(_ id: String) { defaults?.set(pendingHearts(id) + 1, forKey: "hiello.heart." + id) }
    static func clearPendingHeart(_ id: String) { defaults?.removeObject(forKey: "hiello.heart." + id) }

    /// The 1, 2 beat: a widget moves for a while when something new lands (or when Play is tapped), then rests.
    static let beatLength: TimeInterval = 10 * 60
    static func beatWindow(scope: String, key: String, now: Date) -> ClosedRange<Date>? {
        let d = defaults
        if d?.string(forKey: "hiello.beatkey." + scope) != key {
            d?.set(key, forKey: "hiello.beatkey." + scope)
            d?.set(now.timeIntervalSince1970, forKey: "hiello.beatstart." + scope)
        }
        let t = d?.double(forKey: "hiello.beatstart." + scope) ?? 0
        let start = t > 0 ? Date(timeIntervalSince1970: t) : now
        let end = start.addingTimeInterval(beatLength)
        return now < end ? start...end : nil
    }
    static func replay(scope: String) { defaults?.set(Date().timeIntervalSince1970, forKey: "hiello.beatstart." + scope) }
}

// MARK: - Timeline

struct HPhoto {
    var id: String
    var link: String
    var from: String
    var note: String
    var at: Date
    var image: UIImage?
    var isNew: Bool
    var newCount: Int
    var hearts: Int
    var isVideo: Bool
    var canHeart: Bool
    var status: String?
    var frames: [UIImage] = []   // a Flip: quick pictures taken one after another

    /// What the widget beats between: picture 1, picture 2 (older 3-picture Flips use their first and last).
    var beat: [UIImage] {
        if frames.count >= 2 { return [frames[0], frames[frames.count - 1]] }
        return image.map { [$0] } ?? []
    }
}

enum HState {
    case notSetUp
    case empty(String)
    case photo(HPhoto)
}

struct HEntry: TimelineEntry {
    let date: Date
    let state: HState
    var title: String = "Hiello"
    var people: [HPhoto] = []          // whose hi's take turns on the widget (newest first, up to 3)
    var beat: ClosedRange<Date>? = nil // while set, the widget moves 1, 2, 1, 2 by itself
    var minute: Date? = nil            // the minute this entry covers (six 10-second turns)
    var scope: String = "all"
    var debug: String = ""              // temporary test strip: where the pictures came from
    var turn: Int = 0                   // which person's hi this entry shows
    var frame: Int = 0                  // picture 1 (0) or picture 2 (1) of a Flip
    var tick: Int = 0                   // entry number (test strip)
}

// MARK: - Loading (the widget fetches by itself, so it updates even when the app is closed)

enum HLoader {
    static func parseDate(_ s: String?) -> Date? {
        guard var s = s else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone, .withDashSeparatorInDate]
        return f.date(from: s.replacingOccurrences(of: " ", with: "T"))
    }

    static func headers(_ cfg: HConfig, _ req: inout URLRequest) {
        let key = cfg.key ?? ""
        req.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("eyJ") { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
    }

    static func rpc(_ cfg: HConfig, _ fn: String, _ body: [String: Any]) async -> Data? {
        guard let base = cfg.url, let url = URL(string: base + "/rest/v1/rpc/" + fn) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers(cfg, &req)
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode < 300 else { return nil }
        return data
    }

    /// Small pictures are kept in the shared folder so they show instantly next time (and when offline).
    static func image(_ cfg: HConfig, path: String?, maxSide: CGFloat = 700) async -> UIImage? {
        guard let path = path, !path.isEmpty, let dir = HStore.dir else { return nil }
        let name = (maxSide > 700 ? "wf2_" : "w_") + path.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent(name)
        if let img = UIImage(contentsOfFile: file.path) { return img }
        guard let base = cfg.url, let url = URL(string: base + "/storage/v1/object/authenticated/media/" + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        headers(cfg, &req)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode < 300,
              let img = downsized(data, max: maxSide) else { return nil }
        if let jpg = img.jpegData(compressionQuality: 0.85) { try? jpg.write(to: file, options: .atomic) }
        return img
    }

    static func localImage(_ file: String, maxSide: CGFloat = 700) -> UIImage? {
        guard let dir = HStore.dir, let d = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return downsized(d, max: maxSide)
    }

    /// A Flip arrives as one wide picture with its frames side by side; cut it back into frames.
    static func flipFrames(_ img: UIImage?) -> [UIImage] {
        guard let img = img, let cg = img.cgImage else { return [] }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard h > 0 else { return [] }
        let n = Int((w / h).rounded())
        guard n >= 2, n <= 7 else { return [] }
        let fw = w / CGFloat(n)
        var out: [UIImage] = []
        for i in 0..<n {
            let r = CGRect(x: (CGFloat(i) * fw).rounded(), y: 0, width: fw.rounded(.down), height: h)
            if let c = cg.cropping(to: r) { out.append(UIImage(cgImage: c)) }
        }
        return out
    }

    /// Widgets have a small memory budget, so pictures are shrunk to what the widget can show.
    static func downsized(_ data: Data, max side: CGFloat = 700) -> UIImage? {
        guard let img = UIImage(data: data) else { return nil }
        let s = img.size
        guard s.width > side || s.height > side else { return img }
        let k = side / Swift.max(s.width, s.height)
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Newer servers leave out your own hi's (backend/circle.sql); older ones send everything.
    static func feedData(_ cfg: HConfig) async -> Data? {
        let args: [String: Any] = ["p_fid": cfg.fid ?? "", "p_sec": cfg.sec ?? ""]
        if let mid = cfg.mid, !mid.isEmpty, let d = await rpc(cfg, "hi_widget_feed", args.merging(["p_member": mid]) { a, _ in a }) { return d }
        return await rpc(cfg, "hi_widget_feed", args)
    }

    static func entries(person: String?, family: WidgetFamily) async -> [HEntry] {
        let now = Date()
        guard let cfg = HStore.config() else { return [HEntry(date: now, state: .notSetUp)] }
        let isGP = (cfg.role ?? "gp") == "gp"
        let who = (person == nil || person == "Everyone" || person == "") ? nil : person
        var photos: [HPhoto] = []
        var dbg = "me " + String((cfg.mid ?? "none").prefix(4))

        // 1) the family's server (fresh)
        if cfg.url != nil, cfg.fid != nil, cfg.sec != nil,
           let data = await feedData(cfg),
           let feed = try? JSONDecoder().decode(HFeed.self, from: data) {
            let mine = cfg.mid ?? ""
            dbg += " · srv \((feed.posts ?? []).count) mine \((feed.posts ?? []).filter { $0.member_id == mine }.count)"
            var rows: [(HRow, Bool)] = []
            for r in feed.posts ?? [] where r.member_id != mine && (who == nil || r.from_name == who) { rows.append((r, false)) }
            for r in feed.replies ?? [] where r.member_id != mine && r.thumb_path != nil && (who == nil || r.from_name == who) { rows.append((r, true)) }
            let when = { (r: HRow) -> Date in parseDate(r.shown_at) ?? parseDate(r.created_at) ?? now }
            rows.sort { when($0.0) > when($1.0) }
            let unseen = isGP ? rows.filter { !$0.1 && $0.0.watched_at == nil }.count : 0
            for (r, isReply) in turns(rows, by: { $0.0.from_name ?? $0.0.member_id ?? $0.0.id }) {
                let pending = isReply ? 0 : HStore.pendingHearts(r.id)
                if !isReply, (r.hearts ?? 0) >= pending, pending > 0 { HStore.clearPendingHeart(r.id) }
                let isFlip = r.media_kind == "flip"
                let pic = await image(cfg, path: r.thumb_path, maxSide: isFlip ? 1100 : 700)
                let frames = isFlip ? flipFrames(pic) : []
                photos.append(HPhoto(id: r.id, link: (isReply ? "hiello://reply/" : "hiello://post/") + r.id,
                                     from: r.from_name ?? "", note: r.note ?? "",
                                     at: parseDate(r.created_at) ?? now, image: frames.first ?? pic,
                                     isNew: isGP && !isReply && r.watched_at == nil, newCount: unseen,
                                     hearts: Swift.max(r.hearts ?? 0, pending), isVideo: r.media_kind == "video",
                                     canHeart: isGP && !isReply, status: nil,
                                     frames: frames))
            }
        }

        if photos.isEmpty { dbg += " · LOCAL \((cfg.items ?? []).count) mine \((cfg.items ?? []).filter { $0.mine == true }.count)" }
        else { dbg += " · show " + photos.map { String($0.from.prefix(5)) + ($0.frames.count > 1 ? "(F)" : "") }.joined(separator: ",") }
        // 2) what the app left on the phone (offline, or the one-phone demo)
        if photos.isEmpty, let items = cfg.items, !items.isEmpty {
            let list = items.filter { (who == nil || $0.from == who) && (cfg.demo == true || $0.mine != true) }
            let unseen = list.filter { !$0.watched }.count
            for it in turns(list, by: { $0.from }) {
                let isFlip = it.flip ?? false
                let pic = localImage(it.file, maxSide: isFlip ? 1100 : 700)
                let frames = isFlip ? flipFrames(pic) : []
                photos.append(HPhoto(id: it.id, link: "hiello://post/" + it.id, from: it.from, note: it.note,
                                     at: Date(timeIntervalSince1970: it.at / 1000), image: frames.first ?? pic,
                                     isNew: isGP && !it.watched, newCount: isGP ? unseen : 0,
                                     hearts: Swift.max(it.hearts, HStore.pendingHearts(it.id)), isVideo: it.video ?? false,
                                     canHeart: isGP && cfg.demo != true, status: nil,
                                     frames: frames))
            }
        }

        let title = who.map { "Hiello \u{00B7} " + $0 } ?? "Hiello"
        if photos.isEmpty {
            let msg = "When someone in your Circle sends a hi, it shows up right here."
            return [HEntry(date: now, state: .empty(msg), title: title)]
        }

        // The newest hi leads. If it's a Flip it beats 1, 2, 1, 2; if a few people sent hi's lately,
        // they take turns every 10 seconds. It moves for an hour after something new lands, then rests
        // on the newest one (tap Play to see it move again).
        // Others only take turns if they sent something in the last week (old hi's don't hang around).
        photos = [photos[0]] + photos.dropFirst().filter { now.timeIntervalSince($0.at) < 7 * 86400 }
        let main = photos[0]
        let scope = who ?? "all"
        let moving = photos.count > 1 || main.beat.count > 1
        if moving {
            // The flip, the way Apple supports: a timeline of separate frames. Picture 1, picture 2, … one
            // per second for the first minute, then one every 3 seconds for the next 6 minutes; a few people's
            // hi's take turns every 10 frames. Then it rests on the newest and iOS asks for a fresh timeline.
            if let e = cfg.err, !e.isEmpty { dbg += " · err " + e }
            let w = now...now.addingTimeInterval(7 * 60)
            var out: [HEntry] = []
            var t = 0.0
            for k in 0..<180 {
                let n = photos.count
                let who = (k / 10) % n
                let frames = Swift.max(photos[who].beat.count, 1)
                out.append(HEntry(date: now.addingTimeInterval(t), state: .photo(photos[who]), title: title, people: photos,
                                  beat: w, minute: nil, scope: scope, debug: dbg, turn: who, frame: k % frames, tick: k))
                t += k < 60 ? 1 : 3
            }
            out.append(HEntry(date: now.addingTimeInterval(t), state: .photo(main), title: title, people: photos,
                              beat: nil, scope: scope, debug: dbg, tick: 180))
            return out
        }
        return [HEntry(date: now, state: .photo(main), title: title, people: photos, beat: nil, scope: scope, debug: dbg)]
    }

    /// The newest hi from each person, newest first, at most 3 people (so the turns divide a minute evenly).
    /// Who takes turns on the widget (3 at most, so the turns divide a minute evenly): the newest hi from each
    /// person first; if fewer than 3 people sent one, their next most recent hi's fill the turns.
    static func turns<T>(_ list: [T], by key: (T) -> String) -> [T] {
        var seen = Set<String>(), out: [T] = [], rest: [T] = []
        for x in list {
            if seen.contains(key(x)) { rest.append(x) } else { seen.insert(key(x)); out.append(x) }
        }
        out = Array(out.prefix(3))
        for x in rest where out.count < 3 { out.append(x) }
        return out
    }

    /// For the Hiello Lab widget: where the pictures come from.
    static func sourceReport() async -> String {
        guard let cfg = HStore.config() else { return "no setup" }
        let mine = cfg.mid ?? ""
        var srv = "srv ✗"
        if cfg.url != nil, let data = await feedData(cfg), let feed = try? JSONDecoder().decode(HFeed.self, from: data) {
            let posts = feed.posts ?? []
            srv = "srv \(posts.count) others \(posts.filter { $0.member_id != mine }.count)"
        }
        let items = cfg.items ?? []
        return srv + " · local \(items.count) mine \(items.filter { $0.mine == true }.count) · id \(mine.prefix(4))"
    }

    static func sendHeart(_ id: String) async {
        HStore.addPendingHeart(id)
        guard let cfg = HStore.config(), cfg.url != nil, cfg.fid != nil else { return }
        _ = await rpc(cfg, "hi_heart", ["p_fid": cfg.fid ?? "", "p_sec": cfg.sec ?? "", "p_post": id])
    }
}

// MARK: - Choosing whose photos (one widget per grandkid, like Locket's best-friend widgets)

struct PeopleOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Everyone"] + (HStore.config()?.people ?? [])
    }
    func defaultResult() async -> String? { "Everyone" }
}

struct PickPersonIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Whose photos?"
    static var description = IntentDescription("Show everyone's Hiellos, or just one person's.")

    @Parameter(title: "Show photos from", optionsProvider: PeopleOptions())
    var person: String?

    init() {}
}

// MARK: - Send love straight from the home screen (Locket can't)

struct HeartIntent: AppIntent {
    static var title: LocalizedStringResource = "Send love"
    static var description = IntentDescription("Send a heart back to whoever sent this Hiello.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Hiello")
    var postId: String

    init() {}
    init(postId: String) { self.postId = postId }

    func perform() async throws -> some IntentResult {
        await HLoader.sendHeart(postId)
        return .result()
    }
}

/// Play: start the 1, 2 beat again after the widget has come to rest.
struct PlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Play"
    static var description = IntentDescription("Make the Hiello widget move again.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Widget")
    var scope: String

    init() {}
    init(scope: String) { self.scope = scope }

    func perform() async throws -> some IntentResult {
        HStore.replay(scope: scope)
        return .result()
    }
}

// MARK: - Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HEntry {
        HEntry(date: Date(), state: .empty("New photos from the family will pop up right here."))
    }

    func snapshot(for configuration: PickPersonIntent, in context: Context) async -> HEntry {
        let list = await HLoader.entries(person: configuration.person, family: context.family)
        return list.first ?? placeholder(in: context)
    }

    func timeline(for configuration: PickPersonIntent, in context: Context) async -> Timeline<HEntry> {
        let list = await HLoader.entries(person: configuration.person, family: context.family)
        // Check the family's server again in about 15 minutes (iOS decides the exact moment).
        let moving = list.contains { $0.beat != nil }
        return Timeline(entries: list, policy: moving ? .atEnd : .after(Date().addingTimeInterval(15 * 60)))
    }
}

// MARK: - Views

func agoText(_ d: Date, now: Date) -> String {
    let m = Int(now.timeIntervalSince(d) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min ago" }
    let h = m / 60
    if h < 24 { return "\(h)h ago" }
    let days = h / 24
    return days == 1 ? "yesterday" : "\(days) days ago"
}

// MARK: - The 1, 2 beat
//
// A widget can't play video or GIFs, but a timer label ticks by itself every second while the widget is on
// screen. iOS draws that timer character by character in whatever font we give it. Hiello's two stencil
// fonts (scripts/make_mask_fonts.py) draw each digit as either a block far bigger than the widget or nothing,
// so a timer in one of them is a stencil that is open whenever ANY of its characters is a solid one.
// Using only short 10-second timers, whose text only ever holds 0, 1 and one changing digit:
//   HielloOdd on a count-up  -> open on odd seconds          (picture 2's beat)
//   HielloNZ  on a count-up  -> open once that timer started (this turn has begun)
//   HielloNZ  on a countdown -> open until that timer ends   (this turn isn't over)
// Each 10-second turn is a picture-1 layer and a picture-2 layer, later turns stacked on top of earlier ones.
// Every layer carries its own picture AND caption, so if anything ever failed you'd still see the newest hi.
// Only public SwiftUI/WidgetKit is used.

struct StencilMask: View {
    var font: String
    var range: ClosedRange<Date>
    var down: Bool = false
    var body: some View {
        GeometryReader { g in
            Text(timerInterval: range, countsDown: down)
                .font(.custom(font, fixedSize: max(g.size.width, g.size.height, 1)))
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color.black)
                .frame(width: g.size.width, height: g.size.height)
        }
    }
}

extension View {
    /// Visible only during the 10-second turn starting at `s`; `second` = only on its odd seconds (picture 2).
    func inTurn(_ s: Date, second: Bool) -> some View {
        self.mask(second ? StencilMask(font: "HielloOdd", range: s...s.addingTimeInterval(10))
                         : StencilMask(font: "HielloNZ", range: s.addingTimeInterval(-1)...s.addingTimeInterval(9)))
            .mask(StencilMask(font: "HielloNZ", range: s...s.addingTimeInterval(11), down: true))
    }
}

struct FillImage: View {
    var image: UIImage
    var body: some View {
        Color.clear
            .overlay(Image(uiImage: image).resizable().scaledToFill())
            .clipped()
    }
}

/// One picture with its own shade and caption: a whole, ready-to-show widget face.
struct Face: View {
    var photo: HPhoto
    var image: UIImage?
    var now: Date
    @Environment(\.widgetFamily) var family
    var body: some View {
        let small = family == .systemSmall, big = family == .systemLarge
        ZStack {
            HB.midnight
            if let img = image {
                FillImage(image: img)
            } else {
                LinearGradient(colors: [Color(red: 27/255, green: 49/255, blue: 102/255), HB.midnight], startPoint: .top, endPoint: .bottom)
                HeartBadge(size: 54).opacity(0.5)
            }
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [.clear, Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: small ? 44 : (big ? 80 : 56))
            }
            Caption(photo: photo, now: now, heartRoom: photo.canHeart)
        }
    }
}

/// The face this timeline entry shows: one person's hi, picture 1 or picture 2.
struct BeatStack: View {
    var entry: HEntry
    var people: [HPhoto]
    var body: some View {
        let who = people[Swift.min(entry.turn, people.count - 1)]
        let pics = who.beat
        Face(photo: who, image: pics.isEmpty ? nil : pics[Swift.min(entry.frame, pics.count - 1)], now: entry.date)
            .transition(.identity)
            .id(entry.tick)
    }
}

/// Who sent it, when, and their note.
struct Caption: View {
    var photo: HPhoto
    var now: Date
    var heartRoom: Bool
    @Environment(\.widgetFamily) var family
    var big: Bool { family == .systemLarge }
    var small: Bool { family == .systemSmall }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !photo.note.isEmpty && !small {
                Text(photo.note)
                    .font(.custom("Baskerville-Bold", size: big ? 22 : 16))
                    .foregroundColor(HB.navy)
                    .lineLimit(big ? 3 : 2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HB.navy, lineWidth: 2))
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .padding(.top, 34)
                    .padding(.trailing, 70)
            }
            Spacer(minLength: 0)
            // one low line: who it's from on the left, how long ago on the right
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(photo.status ?? (photo.from.isEmpty ? "From the family" : "From " + photo.from))
                    .font(.system(size: small ? 11 : (big ? 15 : 13), weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(agoText(photo.at, now: now))
                    .font(.system(size: small ? 11 : (big ? 15 : 13), weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .padding(.trailing, heartRoom ? (small ? 40 : 56) : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, small ? 10 : 13)
        .padding(.top, small ? 10 : 13)
        .padding(.bottom, small ? 7 : 9)
    }
}

struct PhotoView: View {
    var entry: HEntry
    var photo: HPhoto
    @Environment(\.widgetFamily) var family

    var big: Bool { family == .systemLarge }
    var small: Bool { family == .systemSmall }
    var people: [HPhoto] { entry.people.isEmpty ? [photo] : entry.people }
    var canMove: Bool { people.count > 1 || photo.beat.count > 1 }

    var body: some View {
        ZStack {
            // the pictures with their captions (in the main layer so the 1, 2 stencils stay live)
            BeatStack(entry: entry, people: people)
            TestStrip(entry: entry)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if photo.isNew {
                        Text(photo.newCount > 1 ? "\(photo.newCount) NEW" : "NEW")
                            .font(.system(size: small ? 11 : 13, weight: .black))
                            .tracking(1)
                            .foregroundColor(HB.navy)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(HB.pink))
                            .overlay(Capsule().stroke(HB.red, lineWidth: 1.5))
                    }
                    Spacer()
                    if false && canMove {
                        // resting: Play starts the 1, 2 again
                        Button(intent: PlayIntent(scope: entry.scope)) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: small ? 11 : 13, weight: .bold))
                                Text("1, 2").font(.system(size: small ? 12 : 14, weight: .black))
                            }
                            .foregroundColor(HB.navy)
                            .padding(.horizontal, small ? 9 : 12).padding(.vertical, small ? 6 : 7)
                            .background(Capsule().fill(Color.white))
                            .overlay(Capsule().stroke(HB.pink, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    if photo.isVideo {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: small ? 11 : 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    if photo.canHeart {
                        Button(intent: HeartIntent(postId: photo.id)) {
                            HStack(spacing: 4) {
                                HeartBadge(size: small ? 20 : 26)
                                if photo.hearts > 0 && !small {
                                    Text("\(photo.hearts)")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundColor(HB.navy)
                                }
                            }
                            .padding(.horizontal, small ? 7 : 10).padding(.vertical, small ? 6 : 7)
                            .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(small ? 11 : 14)
        }
        .widgetURL(tapLink)
    }

    /// Tapping opens the hi that's on screen: the app works out whose turn it was from these.
    var tapLink: URL? { URL(string: people[Swift.min(entry.turn, people.count - 1)].link) }
}

struct MessageView: View {
    var text: String
    var setUp: Bool
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                HeartBadge(size: family == .systemSmall ? 18 : 22)
                Text("Hiello").font(.custom("Baskerville-Bold", size: family == .systemSmall ? 18 : 22)).foregroundColor(.white)
            }
            Text(setUp ? text : "Open Hiello to connect your family.")
                .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .widgetURL(URL(string: "hiello://home"))
    }
}

struct HielloWidgetView: View {
    var entry: HEntry
    @Environment(\.widgetFamily) var family

    var photo: HPhoto? { if case .photo(let p) = entry.state { return p } else { return nil } }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    LogoHeart().fill(Color.white).frame(width: 22, height: 21)
                    if let p = photo, p.newCount > 0 { Text("\(p.newCount)").font(.system(size: 14, weight: .black)) }
                }
            }
            .widgetURL(URL(string: photo?.link ?? "hiello://home"))
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    LogoHeart().fill(Color.white).frame(width: 13, height: 12)
                    Text("Hiello").font(.system(size: 13, weight: .heavy))
                }
                if let p = photo {
                    Text(p.isNew ? "New from \(p.from)" : (p.status ?? "From \(p.from)"))
                        .font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(p.note.isEmpty ? agoText(p.at, now: entry.date) : p.note).font(.system(size: 13)).lineLimit(1)
                } else {
                    Text("All caught up").font(.system(size: 15, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: photo?.link ?? "hiello://home"))
            .containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                switch entry.state {
                case .photo(let p): PhotoView(entry: entry, photo: p)
                case .empty(let msg): MessageView(text: msg, setUp: true)
                case .notSetUp: MessageView(text: "", setUp: false)
                }
            }
            // The photo is the widget's background, so it fills edge to edge (and in StandBy on the nightstand).
            .containerBackground(for: .widget) { HB.midnight }
        }
    }
}

// MARK: - Widgets

struct HielloWidget: Widget {
    let kind = "HielloWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PickPersonIntent.self, provider: Provider()) { entry in
            HielloWidgetView(entry: entry)
        }
        .configurationDisplayName("Hiello")
        .description("Your Circle's hi's on your home screen. Flips move 1, 2, 1, 2.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

// MARK: - Hiello Lab: a test widget that shows which way of moving works on this iPhone

struct LabEntry: TimelineEntry {
    let date: Date
    let start: Date
    let tick: Int
    var source: String = ""
}

struct LabProvider: TimelineProvider {
    func placeholder(in context: Context) -> LabEntry { LabEntry(date: Date(), start: Date(), tick: 0) }
    func getSnapshot(in context: Context, completion: @escaping (LabEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LabEntry>) -> Void) {
        Task {
            let now = Date()
            let src = await HLoader.sourceReport()
            // a new entry every 5 seconds for 2 minutes: shows how closely iOS keeps to a quick schedule
            let list = (0..<24).map { LabEntry(date: now.addingTimeInterval(Double($0) * 5), start: now, tick: $0, source: src) }
            completion(Timeline(entries: list, policy: .atEnd))
        }
    }
}

struct LabTile: View {
    var label: String
    var start: Date
    var turns: Bool
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Color.red
                if turns {
                    // the real method: blue, green, blue, green… for two minutes
                    ForEach(0..<12, id: \.self) { j in
                        let s = start.addingTimeInterval(Double(j) * 10)
                        Color.blue.inTurn(s, second: false)
                        Color.green.inTurn(s, second: true)
                    }
                } else {
                    // one long timer: flickers green whenever any digit is odd
                    Color.green.mask(StencilMask(font: "HielloOdd", range: start...start.addingTimeInterval(3600)))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.white)
        }
    }
}

struct LabView: View {
    var entry: LabEntry
    var range: ClosedRange<Date> { entry.start...entry.start.addingTimeInterval(3600) }
    var fontsOK: Bool { UIFont(name: "HielloOdd", size: 12) != nil && UIFont(name: "HielloNZ", size: 12) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Lab").font(.system(size: 12, weight: .black)).foregroundColor(HB.pink)
                Text(timerInterval: range, countsDown: false)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .foregroundColor(.white)
                Text(fontsOK ? "F✓" : "F✗").font(.system(size: 11, weight: .black)).foregroundColor(fontsOK ? .green : .red)
                Text("E\(entry.tick)").font(.system(size: 11, weight: .black)).foregroundColor(.white)
            }
            HStack(spacing: 6) {
                LabTile(label: "A", start: entry.start, turns: false)
                LabTile(label: "B", start: entry.start, turns: true)
                VStack(spacing: 2) {
                    // the timer drawn straight in the test font: a green square on odd seconds if the font works,
                    // plain digits if iOS isn't using the font at all
                    ZStack {
                        Color.red
                        Text(timerInterval: range, countsDown: false)
                            .font(.custom("HielloOdd", fixedSize: 34))
                            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                            .lineLimit(1).fixedSize()
                            .foregroundColor(.green)
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("C").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                }
                VStack(spacing: 2) {
                    ZStack { Color.red; Color.green.opacity(entry.tick % 2 == 1 ? 1 : 0) }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("D").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                }
            }
            ProgressView(timerInterval: entry.start...entry.start.addingTimeInterval(60), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(HB.pink)
            Text(entry.source).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.8)).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { HB.midnight }
    }
}

/// TEMPORARY test strip on the Hiello widget (remove before release): source of the pictures, fonts,
/// and two tiny every-second tests (S = the stencil method, T = a plain timer).
struct TestStrip: View {
    var entry: HEntry
    var fontsOK: Bool { UIFont(name: "HielloOdd", size: 12) != nil && UIFont(name: "HielloNZ", size: 12) != nil }
    var body: some View {
        let start = entry.beat?.lowerBound ?? entry.date
        VStack {
            HStack(spacing: 4) {
                Text("E\(entry.tick)")
                    .font(.system(size: 9, weight: .black).monospacedDigit())
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(entry.frame == 1 ? Color.green : Color.blue))
                Text(timerInterval: start...start.addingTimeInterval(3600), countsDown: false)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .frame(width: 30)
                Text((fontsOK ? "F✓ " : "F✗ ") + entry.debug)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .padding(.top, 4).padding(.horizontal, 4)
            Spacer()
        }
    }
}

struct HielloLab: Widget {
    let kind = "HielloLab"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LabProvider()) { entry in LabView(entry: entry) }
            .configurationDisplayName("Hiello Lab (test)")
            .description("A test of how widgets can move on this iPhone.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HielloWidgetBundle: WidgetBundle {
    var body: some Widget {
        HielloWidget()
        HielloLab()
    }
}
