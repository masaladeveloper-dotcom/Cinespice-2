import SwiftUI
import UIKit

/// Semantic palettes shared by every library surface. Player stays cinema black.
enum CinespiceTheme: String, CaseIterable, Identifiable {
    case ember, midnight, pearl, sage
    var id: String { rawValue }
    var title: String {
        switch self { case .ember: return "Ember · Dark"; case .midnight: return "Midnight · Dark"; case .pearl: return "Pearl · Light"; case .sage: return "Sage · Light" }
    }
    var scheme: ColorScheme { self == .ember || self == .midnight ? .dark : .light }
    var background: Color { color([0x101014, 0x0D1424, 0xF8F4EF, 0xF1F6F2]) }
    var surface: Color { color([0x202026, 0x1C2940, 0xE9E2DA, 0xDFEAE2]) }
    var accent: Color { color([0xFF774A, 0x91ADFF, 0xA63D25, 0x226347]) }
    var text: Color { scheme == .dark ? Color(white: 0.96) : Color(white: 0.09) }
    var muted: Color { scheme == .dark ? Color(white: 0.69) : Color(white: 0.36) }
    private func color(_ values: [Int]) -> Color {
        let value = values[Self.allCases.firstIndex(of: self)!]
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
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

struct VideoArtwork: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
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
                    LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: failed ? "photo" : "film")
                        .font(.system(size: 28, weight: .ultraLight)).foregroundStyle(theme.muted.opacity(0.5))
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
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    let video: TelegramVideo
    var wide = false
    var opening = false
    @State private var savingHistory = false
    @State private var savingList = false
    let play: (Bool) -> Void
    let download: () -> Void
    let export: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { play(true) } label: {
                ZStack(alignment: .bottomLeading) {
                    VideoArtwork(video: video)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(video.formatLabel).font(.system(size: 8, weight: .bold)).padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                            if library.display(video).isDownloaded { Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Downloaded") }
                            Spacer()
                            if video.duration > 0 { Text(duration(video.duration)).font(.system(size: 10, weight: .semibold, design: .monospaced)) }
                        }
                        if let progress = library.snapshot.history[video.id], progress.canResume {
                            ProgressView(value: progress.fraction).tint(theme.accent).background(Color.white.opacity(0.2))
                        }
                    }.padding(12).foregroundStyle(.white)
                    if opening { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .aspectRatio(wide ? 16 / 9 : 0.73, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }.buttonStyle(CinespiceButtonStyle()).accessibilityLabel("Play \(video.title)")
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
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
                    }.font(.caption2).foregroundStyle(theme.accent)
                    if savingList { ProgressView("Saving list…").font(.caption2) }
                    if savingHistory { ProgressView("Saving history…").font(.caption2) }
                    else if library.snapshot.history[video.id]?.completed == true { Text("Watched").font(.caption2).foregroundStyle(theme.accent) }
                    Text(library.snapshot.collections.first(where: { $0.id == video.chatID })?.title ?? "Telegram")
                        .font(.system(size: 10)).foregroundStyle(theme.muted).lineLimit(1)
                }
                Menu {
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
                    Button("Play / resume") { play(true) }
                    Button("Play from beginning") { play(false) }
                    if telegram.fullDownloads.contains(video.fileID) {
                        Button("Cancel download") { Task { await telegram.cancelDownload(video) } }.disabled(telegram.cancellingDownloads.contains(video.fileID))
                    } else { Button("Download first") { download() }.disabled(telegram.preparingDownloads.contains(video.id)) }
                    if library.display(video).isDownloaded { Button("Save to Files…", action: export) }
                    Button("Mark watched") { updateHistory(remove: false) }.disabled(savingHistory)
                    if library.snapshot.history[video.id] != nil {
                        Button("Remove from watch history") { updateHistory(remove: true) }.disabled(savingHistory)
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(CinespiceButtonStyle())
                .accessibilityLabel("Options for \(video.title)")
            }
        }.foregroundStyle(theme.text)
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
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .ultraLight)).foregroundStyle(theme.accent)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(theme.muted).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 60)
    }
}

struct VideoDetailsView: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    @Environment(\.dismiss) private var dismiss
    let video: TelegramVideo
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VideoArtwork(video: video).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(video.fileName ?? video.title).font(.title2.weight(.bold)).textSelection(.enabled)
                    HStack { Text(video.formatLabel); Text("·"); Text(ByteCountFormatter.string(fromByteCount: video.size, countStyle: .file)) }.font(.subheadline).foregroundStyle(theme.muted)
                    if video.date > 0 { Text(Date(timeIntervalSince1970: Double(video.date)), style: .date).font(.caption).foregroundStyle(theme.muted) }
                    if let caption = video.caption { Text(caption).font(.body).textSelection(.enabled) }
                    Text("File details and artwork are cached on this iPhone. Tap Cinespice to refresh the current channel.").font(.caption).foregroundStyle(theme.muted)
                }.padding(22)
            }.background(theme.background).navigationTitle("File details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(theme.scheme)
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
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    let title: String
    let cancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle())
            VStack(spacing: 16) {
                ProgressView().tint(theme.accent).scaleEffect(1.3).padding(8)
                Text("Loading media…").font(.headline)
                Text("Warming up your cinema.").font(.subheadline).foregroundStyle(.secondary)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                Button(action: cancel) {
                    Text("Cancel").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 100, minHeight: 44)
                        .background(.white.opacity(0.1), in: Capsule())
                }.buttonStyle(CinespiceButtonStyle())
            }.padding(28).frame(maxWidth: 330)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
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
