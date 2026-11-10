import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// MARK: - Brand

enum HB {
    static let navy = Color(red: 20/255, green: 40/255, blue: 90/255)       // #14285A
    static let midnight = Color(red: 52/255, green: 48/255, blue: 45/255)   // #34302D warm graphite
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
    var status: String?     // parent widget: "Grandpa watched ✓"
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
    static func image(_ cfg: HConfig, path: String?) async -> UIImage? {
        guard let path = path, !path.isEmpty, let dir = HStore.dir else { return nil }
        let name = "w_" + path.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent(name)
        if let img = UIImage(contentsOfFile: file.path) { return img }
        guard let base = cfg.url, let url = URL(string: base + "/storage/v1/object/authenticated/media/" + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        headers(cfg, &req)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode < 300,
              let img = downsized(data) else { return nil }
        if let jpg = img.jpegData(compressionQuality: 0.85) { try? jpg.write(to: file, options: .atomic) }
        return img
    }

    static func localImage(_ file: String) -> UIImage? {
        guard let dir = HStore.dir, let d = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return downsized(d)
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

    static func entries(person: String?, family: WidgetFamily) async -> [HEntry] {
        let now = Date()
        guard let cfg = HStore.config() else { return [HEntry(date: now, state: .notSetUp)] }
        let gpName = cfg.gp ?? "Grandpa"
        let isGP = (cfg.role ?? "gp") == "gp"
        let who = (person == nil || person == "Everyone" || person == "") ? nil : person
        var photos: [HPhoto] = []

        // 1) the family's server (fresh)
        if cfg.url != nil, cfg.fid != nil, cfg.sec != nil,
           let data = await rpc(cfg, "hi_widget_feed", ["p_fid": cfg.fid ?? "", "p_sec": cfg.sec ?? ""]),
           let feed = try? JSONDecoder().decode(HFeed.self, from: data) {
            let posts = (feed.posts ?? []).filter { who == nil || $0.from_name == who }
            if isGP {
                let unseen = posts.filter { $0.watched_at == nil }
                for r in posts.prefix(6) {
                    let pending = HStore.pendingHearts(r.id)
                    if (r.hearts ?? 0) >= pending, pending > 0 { HStore.clearPendingHeart(r.id) }
                    let pic = await image(cfg, path: r.thumb_path)
                    photos.append(HPhoto(id: r.id, link: "hiello://post/" + r.id, from: r.from_name ?? "", note: r.note ?? "",
                                         at: parseDate(r.created_at) ?? now, image: pic,
                                         isNew: r.watched_at == nil, newCount: unseen.count,
                                         hearts: Swift.max(r.hearts ?? 0, pending), isVideo: r.media_kind == "video",
                                         canHeart: true, status: nil))
                }
            } else {
                // The parent's widget: Grandpa's photos back to you first, then how your Hiellos are doing.
                let mine = cfg.mid ?? ""
                let replies = (feed.replies ?? []).filter { $0.member_id != mine && (who == nil || $0.from_name == who) }
                for r in replies.prefix(3) {
                    let pic = await image(cfg, path: r.thumb_path)
                    photos.append(HPhoto(id: r.id, link: "hiello://reply/" + r.id, from: r.from_name ?? gpName, note: r.note ?? "",
                                         at: parseDate(r.created_at) ?? now, image: pic,
                                         isNew: false, newCount: 0, hearts: 0, isVideo: r.media_kind == "video",
                                         canHeart: false, status: "A hi back from " + (r.from_name ?? gpName)))
                }
                for r in (feed.posts ?? []).prefix(Swift.max(0, 6 - photos.count)) {
                    var st = r.watched_at != nil ? "\(gpName) watched \u{2713}" : "\(gpName) hasn\u{2019}t seen it yet"
                    if (r.hearts ?? 0) > 0 { st += "  \u{2665} \(r.hearts ?? 0)" }
                    let pic = await image(cfg, path: r.thumb_path)
                    photos.append(HPhoto(id: r.id, link: "hiello://post/" + r.id, from: r.from_name ?? "", note: r.note ?? "",
                                         at: parseDate(r.created_at) ?? now, image: pic,
                                         isNew: false, newCount: 0, hearts: r.hearts ?? 0, isVideo: r.media_kind == "video",
                                         canHeart: false, status: st))
                }
                photos.sort { $0.at > $1.at }
            }
        }

        // 2) what the app left on the phone (offline, or the one-phone demo)
        if photos.isEmpty, let items = cfg.items, !items.isEmpty {
            let list = items.filter { who == nil || $0.from == who }
            let unseen = list.filter { !$0.watched }.count
            for it in list.prefix(6) {
                photos.append(HPhoto(id: it.id, link: "hiello://post/" + it.id, from: it.from, note: it.note,
                                     at: Date(timeIntervalSince1970: it.at / 1000), image: localImage(it.file),
                                     isNew: isGP && !it.watched, newCount: isGP ? unseen : 0,
                                     hearts: Swift.max(it.hearts, HStore.pendingHearts(it.id)), isVideo: it.video ?? false,
                                     canHeart: isGP && cfg.demo != true, status: nil))
            }
        }

        let title = who.map { "Hiello \u{00B7} " + $0 } ?? "Hiello"
        if photos.isEmpty {
            let msg = isGP ? "New photos from the family will pop up right here." : "When \(gpName) writes back, it shows up here."
            return [HEntry(date: now, state: .empty(msg), title: title)]
        }

        // Something new: keep showing the newest until it's opened (like Locket).
        if let fresh = photos.first(where: { $0.isNew }) {
            return [HEntry(date: now, state: .photo(fresh), title: title)]
        }
        // Nothing new: slowly go through recent ones, like a photo frame (Locket just sits on the last one).
        let step: TimeInterval = 20 * 60
        let base = floor(now.timeIntervalSince1970 / step)
        var out: [HEntry] = []
        for i in 0..<6 {
            let slot = base + Double(i)
            let idx = Int(slot.truncatingRemainder(dividingBy: Double(photos.count)))
            let d = i == 0 ? now : Date(timeIntervalSince1970: slot * step)
            out.append(HEntry(date: d, state: .photo(photos[idx]), title: title))
        }
        return out
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
        return Timeline(entries: list, policy: .after(Date().addingTimeInterval(15 * 60)))
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

struct PhotoBackground: View {
    var photo: HPhoto?
    var body: some View {
        ZStack {
            HB.midnight
            if let img = photo?.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else if photo != nil {
                LinearGradient(colors: [Color(red: 74/255, green: 69/255, blue: 65/255), HB.midnight], startPoint: .top, endPoint: .bottom)
                HeartBadge(size: 54).opacity(0.5)
            }
        }
    }
}

struct PhotoView: View {
    var entry: HEntry
    var photo: HPhoto
    @Environment(\.widgetFamily) var family

    var big: Bool { family == .systemLarge }
    var small: Bool { family == .systemSmall }

    var body: some View {
        ZStack {
            // bottom shade so the words are readable on any photo
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [.clear, Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: small ? 70 : (big ? 130 : 90))
            }
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
                    if photo.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: small ? 11 : 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                }
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
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let st = photo.status {
                            Text(st)
                                .font(.system(size: small ? 12 : 14, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text(photo.from.isEmpty ? "From the family" : "From " + photo.from)
                                .font(.system(size: small ? 15 : (big ? 22 : 18), weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(agoText(photo.at, now: entry.date))
                            .font(.system(size: small ? 11 : 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
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
        .widgetURL(URL(string: photo.link))
    }
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
            .containerBackground(for: .widget) { PhotoBackground(photo: photo) }
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
        .description("New family photos, right on your home screen. Tap the heart to send love back.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

@main
struct HielloWidgetBundle: WidgetBundle {
    var body: some Widget {
        HielloWidget()
    }
}
