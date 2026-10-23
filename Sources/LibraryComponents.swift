import SwiftUI
import UIKit

/// All surfaces use one palette. Legacy saved names resolve without losing a preference.
enum CinespiceTheme: String, CaseIterable, Identifiable {
    case glass, dark, crimson, silver
    init?(rawValue: String) {
        switch rawValue {
        case "glass", "pearl", "sage": self = .glass
        case "dark", "cinema": self = .dark
        case "crimson", "ember": self = .crimson
        case "silver", "midnight": self = .silver
        default: return nil
        }
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return "Cinespice Glass"
        case .dark: return "Cinespice Dark"
        case .crimson: return "Crimson Cinema"
        case .silver: return "Silver Screen"
        }
    }
    var scheme: ColorScheme { self == .glass ? .light : .dark }
    private var palette: (background: Int, surface: Int, text: Int, muted: Int, accent: Int, action: Int) {
        switch self {
        case .glass: return (0xF8F6F4, 0xFFFFFF, 0x171518, 0x68616A, 0xCC182A, 0xCC182A)
        case .dark: return (0x0B0B0F, 0x1C1C22, 0xF8F6F4, 0xB5AFB9, 0xFF6975, 0xB6111B)
        case .crimson: return (0x1B0D14, 0x311D27, 0xFBF3EC, 0xC5ADB6, 0xF3929E, 0xA32C44)
        case .silver: return (0x14171C, 0x272C34, 0xF5F7FA, 0xB4BDC9, 0xD6DDE7, 0xD6DDE7)
        }
    }
    var background: Color { color(palette.background) }
    var surface: Color { color(palette.surface) }
    var text: Color { color(palette.text) }
    var muted: Color { color(palette.muted) }
    var accent: Color { color(palette.accent) }
    var action: Color { color(palette.action) }
    var onAction: Color { self == .silver ? color(0x14171C) : .white }
    var separator: Color { muted.opacity(0.25) }
    private func color(_ value: Int) -> Color {
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

/// Dimensions derive from the safe content width, including on iPad and rotation.
struct CinespiceLayout {
    static let maximumWidth: CGFloat = 1200
    static let posterRatio: CGFloat = 0.73
    static let gap: CGFloat = 16
    let width: CGFloat
    var gutter: CGFloat { width < 360 ? 16 : (width < 700 ? 24 : 32) }
    var innerWidth: CGFloat { max(1, min(width, Self.maximumWidth) - gutter * 2) }
    func columns(minimum: CGFloat) -> [GridItem] {
        let count = max(1, min(6, Int((innerWidth + Self.gap) / (max(1, minimum) + Self.gap))))
        return Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: count)
    }
}

struct CinespiceWordmark: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    var body: some View {
        (Text("CINE").foregroundColor(theme.text) + Text("SPICE").foregroundColor(theme.accent))
            .font(.headline.weight(.bold)).tracking(2).lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityLabel("Cinespice")
    }
}

/// The paged hero reserves its measured text height rather than clipping larger type.
struct HeroHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Keep the visual label and its hit area together. Opacity/background feedback
/// does not move or shrink the target under the user's finger.
struct CinespiceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var onPressChanged: (Bool) -> Void = { _ in }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .background(configuration.isPressed && isEnabled ? Color.primary.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.65 : 1))
            .onChange(of: configuration.isPressed, perform: onPressChanged)
    }
}

/// Animate the label inside a fixed touch target; respect the system motion preference.
struct CinespicePressStyle: ButtonStyle {
    var onPressChanged: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
            .onChange(of: configuration.isPressed, perform: onPressChanged)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Use native Liquid Glass with the iOS 26 SDK, keeping iOS 16 and older SDK builds supported.
struct CinespiceDockMaterial: ViewModifier {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(theme.surface, in: Capsule())
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                fallback(content)
            }
#else
            fallback(content)
#endif
        }
    }

    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [theme.text.opacity(0.22), theme.text.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75))
    }
}

struct CinespiceFieldStyle: TextFieldStyle {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.body).padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 56)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.separator.opacity(0.4), lineWidth: 0.5))
    }
}

struct VideoArtwork: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    let video: TelegramVideo
    @State private var image: UIImage?
    @State private var failed = false
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 80; cache.totalCostLimit = 32 * 1024 * 1024; return cache
    }()
    static func clearMemory() { memory.removeAllObjects() }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.surface
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    LinearGradient(colors: [theme.accent.opacity(0.12), theme.surface, theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack").font(.system(size: 30, weight: .regular))
                        Text(video.title).font(.caption.weight(.medium)).lineLimit(3).multilineTextAlignment(.center)
                    }.foregroundStyle(theme.muted).padding(18)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityLabel(failed ? "Artwork unavailable" : "Video artwork")
        .task(id: "\(library.accountID ?? 0)_\(video.thumbnailKey)_\(library.artworkGeneration)") {
            image = nil; failed = false
            let key = "\(library.accountID ?? 0)_\(video.thumbnailKey)" as NSString
            if let cached = Self.memory.object(forKey: key) { image = cached; return }
            if let mini = video.minithumbnail { image = UIImage(data: mini) }
            do {
                guard let data = try await telegram.thumbnail(video) else { return }
                try Task.checkCancellation()
                guard let decoded = UIImage(data: data) else { failed = true; return }
                image = decoded
                Self.memory.setObject(decoded, forKey: key, cost: decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count * 4)
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}

struct VideoCard: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let video: TelegramVideo
    var wide = false
    var compact = false
    var opening = false
    @State private var savingHistory = false
    @State private var savingList = false
    let play: (Bool) -> Void
    let download: () -> Void
    let export: () -> Void
    let info: () -> Void

    var body: some View {
        Group {
            if compact {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    artwork.frame(width: dynamicTypeSize.isAccessibilitySize ? 120 : 82)
                    VStack(alignment: .leading, spacing: 8) { metadata; controls }
                }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) { artwork; metadata; controls }
            }
        }.foregroundStyle(theme.text)
            .contextMenu { videoActions }
            .accessibilityAction(named: Text("More info"), info)
    }
    private var artwork: some View {
        Button(action: info) {
            ZStack(alignment: .bottomLeading) {
                VideoArtwork(video: video)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    if !compact { HStack {
                        Text(video.formatLabel).font(.caption2.weight(.semibold)).padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                        if library.display(video).isDownloaded { Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Downloaded") }
                        Spacer()
                        if video.duration > 0 { Text(duration(video.duration)).font(.caption2.monospacedDigit()) }
                    }
                    }
                    if let progress = library.snapshot.history[video.id], progress.canResume {
                        ProgressView(value: progress.fraction).tint(theme.accent).background(Color.white.opacity(0.2))
                    }
                }.padding(12).foregroundStyle(.white)
                if opening { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .aspectRatio(wide ? 16 / 9 : CinespiceLayout.posterRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.text.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            .contentShape(Rectangle())
        }.buttonStyle(CinespicePressStyle()).accessibilityLabel("Details for \(video.title)")
    }
    private var metadata: some View {
        HStack(alignment: .top, spacing: 5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                if telegram.preparingDownloads.contains(video.id) {
                    ProgressView("Preparing download…").font(.caption2)
                } else if telegram.cancellingDownloads.contains(video.fileID) {
                    ProgressView("Cancelling download…").font(.caption2)
                } else if telegram.fullDownloads.contains(video.fileID) {
                    Text("Downloading · \(ByteCountFormatter.string(fromByteCount: library.display(video).downloadedBytes, countStyle: .file))").font(.caption2).foregroundStyle(theme.accent)
                }
                HStack(spacing: 6) {
                    if library.snapshot.savedLists["Favorites"]?.contains(video.id) == true { Image(systemName: "heart.fill").accessibilityLabel("Favorite") }
                    if library.snapshot.savedLists["Watchlist"]?.contains(video.id) == true { Image(systemName: "bookmark.fill").accessibilityLabel("In Watchlist") }
                    if let year = video.filenameYear { Text(String(year)).accessibilityLabel("Filename year \(year)") }
                }.font(.caption).foregroundStyle(theme.muted)
                if savingList { ProgressView("Saving list…").font(.caption2) }
                if savingHistory { ProgressView("Saving history…").font(.caption2) }
                else if library.snapshot.history[video.id]?.completed == true { Text("Watched").font(.caption2).foregroundStyle(theme.accent) }
                if compact && library.display(video).isDownloaded { Label("Downloaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(theme.muted) }
                if compact { Text(ByteCountFormatter.string(fromByteCount: video.size, countStyle: .file)).font(.caption).foregroundStyle(theme.muted) }
                Text(library.snapshot.collections.first(where: { $0.id == video.chatID })?.title ?? "Telegram")
                    .font(.caption).foregroundStyle(theme.muted).lineLimit(1)
            }

        }
    }
    private var controls: some View {
        HStack(spacing: 4) {
            Button { play(true) } label: {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold))
                    .offset(x: 1).frame(width: 34, height: 34)
                    .background(theme.action, in: Circle()).foregroundStyle(theme.onAction)
                    .frame(width: 44, height: 44)
            }.disabled(opening).accessibilityLabel("Play \(video.title)")
            Spacer(minLength: 0)
            Button(action: info) {
                Image(systemName: "info.circle").font(.system(size: 21, weight: .regular))
                    .foregroundStyle(theme.muted).frame(width: 44, height: 44)
            }.accessibilityLabel("More info about \(video.title)")
        }.buttonStyle(CinespicePressStyle())
    }
    @ViewBuilder private var videoActions: some View {
        ForEach(["Favorites", "Watchlist"], id: \.self) { list in
            Button {
                guard !savingList else { return }; savingList = true
                let saved = library.snapshot.savedLists[list]?.contains(video.id) == true
                Task {
                    defer { savingList = false }
                    _ = await library.setSaved(video, list: list, saved: !saved)
                }
            } label: {
                Label((library.snapshot.savedLists[list]?.contains(video.id) == true ? "Remove from " : "Add to ") + list, systemImage: list == "Favorites" ? "heart" : "bookmark")
            }.disabled(savingList)
        }
        Divider()
        Button { play(true) } label: { Label("Play / resume", systemImage: "play.fill") }
        Button { play(false) } label: { Label("Play from beginning", systemImage: "backward.end") }
        Divider()
        if telegram.fullDownloads.contains(video.fileID) {
            Button("Cancel download") { Task { await telegram.cancelDownload(video) } }.disabled(telegram.cancellingDownloads.contains(video.fileID))
        } else { Button(action: download) { Label("Download", systemImage: "arrow.down.circle") }.disabled(telegram.preparingDownloads.contains(video.id)) }
        if library.display(video).isDownloaded { Button(action: export) { Label("Save to Files…", systemImage: "square.and.arrow.up") } }
        Button("Mark watched") { updateHistory(remove: false) }.disabled(savingHistory)
        if library.snapshot.history[video.id] != nil {
            Button("Remove from watch history") { updateHistory(remove: true) }.disabled(savingHistory)
        }
    }
    private func updateHistory(remove: Bool) {
        guard !savingHistory else { return }; savingHistory = true
        Task {
            defer { savingHistory = false }
            if remove { _ = await library.clearHistory(videoID: video.id) }
            else { await library.record(video, position: Double(video.duration), duration: Double(video.duration), completed: true) }
        }
    }
    private func duration(_ seconds: Int) -> String { seconds >= 3600 ? "\(seconds / 3600)h \(seconds / 60 % 60)m" : "\(seconds / 60)m" }
}

struct LibraryEmptyState: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.largeTitle.weight(.regular)).foregroundStyle(theme.muted)
                .frame(minWidth: 44, minHeight: 44)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).font(.subheadline).foregroundStyle(theme.muted).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: 440).padding(.horizontal, 24).padding(.vertical, 40).frame(maxWidth: .infinity)
    }
}

struct VideoDetailsView: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let video: TelegramVideo
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 20))
                    layout {
                        VideoArtwork(video: video).aspectRatio(CinespiceLayout.posterRatio, contentMode: .fit)
                            .frame(maxWidth: 145).clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(video.title).font(.title2.weight(.bold)).textSelection(.enabled)
                            Text(video.formatLabel).font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Label("File information", systemImage: "info.circle").font(.headline)
                        Text(video.fileName ?? video.title).font(.subheadline).textSelection(.enabled)
                        Divider()
                        detailRow("Size", value: ByteCountFormatter.string(fromByteCount: video.size, countStyle: .file))
                        if video.date > 0 {
                            detailRow("Added", value: Date(timeIntervalSince1970: Double(video.date)).formatted(date: .abbreviated, time: .omitted))
                        }
                    }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
                    if let caption = video.caption {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About this video").font(.headline)
                            Text(caption).font(.body).foregroundStyle(theme.muted).textSelection(.enabled)
                        }
                    }
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(theme.background).navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(theme.scheme)
            .foregroundStyle(theme.text).tint(theme.accent).presentationDragIndicator(.visible)
    }
    private func detailRow(_ title: String, value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title).foregroundStyle(theme.muted)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value)
        }.font(.subheadline)
    }
}

/// Geometry gates pagination even when an enclosing VStack is laid out eagerly.
struct LibraryPageTrigger: View {
    let enabled: Bool
    let revision: String
    let viewportHeight: CGFloat
    let action: () -> Void
    var body: some View {
        GeometryReader { geometry in
            let y = geometry.frame(in: .named("library-scroll")).minY
            Color.clear.allowsHitTesting(false).task(id: "\(enabled)_\(revision)_\(Int(y / 100))") {
                guard enabled, y >= -100, y < viewportHeight + 180 else { return }
                action()
            }
        }.frame(height: 1)
    }
}

/// Acknowledges every play tap before Telegram or disk work finishes. Blocks
/// duplicate taps but keeps cancellation available, including with VoiceOver.
struct MediaOpeningOverlay: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .dark
    let title: String
    let cancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle())
            VStack(spacing: 16) {
                ProgressView().tint(theme.accent).scaleEffect(1.3).padding(8)
                Text("Loading media…").font(.headline)
                Text("Getting your video ready.").font(.subheadline).foregroundStyle(.secondary)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                Button(action: cancel) {
                    Text("Cancel").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 100, minHeight: 44)
                        .background(theme.text.opacity(0.08), in: Capsule())
                }.buttonStyle(CinespiceButtonStyle())
            }.padding(28).frame(maxWidth: 330)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 28))
                .padding(24).accessibilityElement(children: .contain)
        }.transition(.opacity)
    }
}

/// Observe taps without cancelling SwiftUI buttons or scroll gestures. Text inputs
/// retain focus; every other tap dismisses the keyboard, including in sheets.
struct KeyboardDismissObserver: UIViewRepresentable {
    final class Host: UIView {
        var attach: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attach?(window) }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var window: UIWindow?
        lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        func attach(_ window: UIWindow?) {
            guard self.window !== window else { return }
            self.window?.removeGestureRecognizer(tap)
            self.window = window
            tap.cancelsTouchesInView = false; tap.delegate = self
            window?.addGestureRecognizer(tap)
        }
        @objc private func dismissKeyboard() { window?.endEditing(true) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Host {
        let view = Host(); view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] in coordinator?.attach($0) }
        return view
    }
    func updateUIView(_ view: Host, context: Context) { }
    static func dismantleUIView(_ view: Host, coordinator: Coordinator) { coordinator.attach(nil); view.attach = nil }
}
