import SwiftUI
import UIKit

struct TelegramLibraryView: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .cinema
    @AppStorage("cinespice.order") private var order: LibraryOrder = .latestRelease
    @Environment(\.scenePhase) private var scenePhase
    @State private var dailySeed = Int(Date().timeIntervalSince1970 / 86400)
    @State private var savedList = "New Releases"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var posterWidth: CGFloat = 160
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var dockSelection
    @Namespace private var librarySelection
    @State private var lastSearchVideo: TelegramVideo?
    @State private var refreshMessage = ""
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rangeServer: TelegramRangeServer
    @State private var countryCode = "+91"
    @State private var homeSeed = UUID().uuidString
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var email = ""
    @State private var emailCode = ""
    @State private var tab = 0
    @State private var viewport = CGSize(width: 390, height: 844)
    @State private var detailsVideo: TelegramVideo?
    @State private var query = ""
    @State private var exportFile: VideoExport?
    @State private var exportDirectory: URL?
    @State private var exporting = false
    @State private var collection: TelegramChat?
    @State private var showCollections = false
    @State private var showSettings = false
    @State private var selection: PlaybackSelection?
    @State private var openingToken = UUID()
    @State private var openingID: String?
    @State private var openingTitle = ""
    @State private var openTask: Task<Void, Never>?
    @State private var playbackError = ""

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if telegram.stage == .ready { libraryScreen.disabled(openingID != nil).accessibilityHidden(openingID != nil) }
            else { authentication }
            if openingID != nil {
                MediaOpeningOverlay(title: openingTitle, cancel: cancelOpening)
                    .zIndex(10)
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.allowsHitTesting(false).onAppear { viewport = geometry.size }.onChange(of: geometry.size) { viewport = $0 }
        })
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .preferredColorScheme(theme.scheme)
        .background(KeyboardDismissObserver().frame(width: 0, height: 0))
        .task { telegram.restoreSession() }
        .onChange(of: scenePhase) { if $0 == .active { dailySeed = Int(Date().timeIntervalSince1970 / 86400) } }
        .sheet(isPresented: $showCollections) { CollectionPicker { chat in showCollections = false; openCollection(chat) } }
        .sheet(item: $exportFile, onDismiss: {
            if let directory = exportDirectory {
                Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
            }
            exportDirectory = nil
        }) { file in VideoExportPicker(file: file) { exportFile = nil } }
        .sheet(item: $detailsVideo) { VideoDetailsView(video: $0) }
        .sheet(isPresented: $showSettings) { LibrarySettingsView() }
        .fullScreenCover(item: $selection) { item in
            VLCPlaybackView(selection: item, library: library) { selection = nil }
        }
        .alert("Could not open video", isPresented: Binding(get: { !playbackError.isEmpty }, set: { if !$0 { playbackError = "" } })) {
            Button("OK") { playbackError = "" }
        } message: { Text(playbackError) }
        .onChange(of: telegram.stage) { stage in
            if stage != .code { code = "" }; if stage != .password { password = "" }; if stage != .emailCode { emailCode = "" }

            if stage != .ready {
                cancelOpening()
                showCollections = false; showSettings = false
                lastSearchVideo = nil; tab = 0; savedList = "New Releases"; selection = nil; exportFile = nil; collection = nil; detailsVideo = nil; query = ""; rangeServer.stop()
            }
        }
    }

    private var browseVideos: [TelegramVideo] {
        order.sort(library.videos)
    }

    private var libraryScreen: some View {
        VStack(spacing: 0) {
            header
            if !refreshMessage.isEmpty { Text(refreshMessage).font(.caption).foregroundStyle(theme.muted).padding(6) }
            if exporting { ProgressView("Preparing export…").font(.caption).tint(theme.accent).padding(10) }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if let collection { collectionPage(collection) }
                        else {
                            switch tab {
                            case 1: personalLibraryPage
                            case 2: searchPage
                            case 3: downloadsPage
                            default: home
                            }
                        }
                        if !library.error.isEmpty { banner(library.error) }
                        if !telegram.status.isEmpty { banner(telegram.status) }
                    }.id("library-top").padding(.bottom, 24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
                }.coordinateSpace(name: "library-scroll")
                    .scrollDismissesKeyboard(.interactively)
                    .id("\(tab)_\(collection?.id ?? 0)_\(library.sessionID)")
                    .onChange(of: savedList) { _ in scroll.scrollTo("library-top", anchor: .top) }
            }
        }

        .safeAreaInset(edge: .bottom, spacing: 0) { tabs }
        .buttonStyle(CinespicePressStyle())
        .task(id: refreshMessage) {
            guard !refreshMessage.isEmpty else { return }
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            refreshMessage = ""
        }
        .task(id: "\(showCollections)_" + library.selectedCollections.map { String($0.id) }.joined(separator: ",")) {
            guard !showCollections else { return }
            for chat in library.selectedCollections { telegram.ensureChat(chat.id) }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if collection != nil {
                Button { collection = nil } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.accessibilityLabel("Back to library")
            }
            Button(action: refreshCurrentPage) {
                Text("cinespice").tracking(-0.8).font(.system(size: 25, weight: .bold))
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(theme.text)
            }.accessibilityLabel("Cinespice, refresh current library")
            Spacer(minLength: 0)
            Button { showCollections = true } label: { Image(systemName: "rectangle.stack").font(.system(size: 18, weight: .medium)).frame(width: 40, height: 40).background(theme.surface, in: Circle()).frame(width: 44, height: 44) }.accessibilityLabel("Channels and groups")
            Button { showSettings = true } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 30, weight: .regular)).foregroundStyle(theme.muted).frame(width: 44, height: 44) }.accessibilityLabel("Profile and settings")
        }.padding(.horizontal, 20).padding(.vertical, 6).background(theme.background.opacity(0.96)).buttonStyle(CinespicePressStyle())
    }

    private func refreshCurrentPage() {
        if tab == 2, collection == nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                let searched = query
                await telegram.searchVideos(searched)
                guard query == searched else { return }
                lastSearchVideo = telegram.videoSearchResults.first
            }
            refreshMessage = "Refreshing search…"
        } else if let chat = collection {
            telegram.loadChat(chat.id, refresh: true)
            refreshMessage = "Refreshing " + chat.title + "…"
        } else if !library.selectedCollections.isEmpty {
            for chat in library.selectedCollections { telegram.loadChat(chat.id, refresh: true) }
            refreshMessage = "Refreshing selected sources, one page at a time…"
        } else { refreshMessage = "Select sources using the channel icon." }
    }

    private var sortControl: some View {
        Menu {
            Picker("Sort videos", selection: $order) { ForEach(LibraryOrder.allCases, id: \.self) { Text($0.title).tag($0) } }
        } label: { Label(order.title, systemImage: "arrow.up.arrow.down").font(.caption.weight(.semibold)).frame(minHeight: 44) }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 32) {
            heroCarousel
            if !library.continueWatching.isEmpty { rail("Continue Watching", subtitle: "", videos: Array(library.continueWatching.prefix(12)), wide: false) }
            if library.selectedCollections.isEmpty {
                LibraryEmptyState(symbol: "rectangle.stack", title: "Your cinema starts here", detail: "Choose channels above to start exploring your videos.")
            }
            ForEach(library.selectedCollections) { chat in
                let videos = homeVideos(chat.id)
                VStack(alignment: .leading, spacing: 12) {
                    Button { openCollection(chat) } label: {
                        HStack {
                            Text(chat.title).font(.title3.weight(.bold)).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                        }.foregroundStyle(theme.text).padding(.horizontal, 20).frame(minHeight: 44)
                    }.accessibilityLabel("Open " + chat.title)
                    if videos.isEmpty {
                        Text("No videos loaded yet. Open this channel to browse.").font(.subheadline).foregroundStyle(theme.muted).padding(.horizontal, 20)
                    } else { posterRail(videos, wide: false) }
                }
            }
            if !telegram.loadingCollections.isEmpty { ProgressView("Loading a small page…").frame(maxWidth: .infinity).font(.caption).tint(theme.accent) }
        }
    }

    // Stable within a launch, varied on the next launch. Never changes resume ordering.
    private func homeVideos(_ chatID: Int64) -> [TelegramVideo] {
        func rank(_ id: String) -> UInt64 {
            (homeSeed + id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        return Array(library.videos.filter { $0.chatID == chatID }.sorted {
            let left = rank($0.id), right = rank($1.id)
            return left == right ? $0.id < $1.id : left < right
        }.prefix(15))
    }

    private var heroHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 560 : min(500, max(340, viewport.height * 0.52)) }
    private var dailyVideo: TelegramVideo? {
        let items = library.videos.sorted { $0.id < $1.id }
        guard !items.isEmpty else { return nil }
        var seed = UInt64(dailySeed) &+ 0x9E3779B97F4A7C15
        seed = (seed ^ (seed >> 30)) &* 0xBF58476D1CE4E5B9
        seed = (seed ^ (seed >> 27)) &* 0x94D049BB133111EB
        return items[Int((seed ^ (seed >> 31)) % UInt64(items.count))]
    }
    private var heroCarousel: some View {
        // Seven editorial positions; no fabricated catalogue results.
        TabView {
            heroSlot("Recently added", video: LibraryOrder.newest.sort(library.videos).first, empty: "Add a source to discover your videos.").tag(0)
            heroSlot("Today's pick", video: dailyVideo, empty: "Your daily pick appears when videos are indexed.").tag(1)
            ForEach(0..<4) { index in
                heroSlot("Trending · \(index + 1)", video: nil, empty: "Catalogue connection coming later. No trending data connected yet.").tag(index + 2)
            }
            heroSlot("Last searched", video: lastSearchVideo.flatMap { library.snapshot.selected.contains($0.chatID) ? $0 : nil }, empty: "Search for a video to fill this spot.").tag(6)
        }.tabViewStyle(.page(indexDisplayMode: .always)).indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: heroHeight + 66)
    }
    private func heroSlot(_ title: String, video: TelegramVideo?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted).padding(.horizontal, 20).padding(.vertical, 8)
            if let video { hero(video) }
            else {
                ZStack {
                    LinearGradient(colors: [theme.accent.opacity(0.2), theme.surface], startPoint: .topTrailing, endPoint: .bottomLeading)
                    LibraryEmptyState(symbol: title.hasPrefix("Trending") ? "sparkles" : "play.rectangle", title: title, detail: empty)
                }.frame(height: heroHeight).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(.horizontal, 20)
            }
            Spacer(minLength: 28)
        }
    }
    @ViewBuilder private var releaseSortHint: some View {
        if order == .latestRelease || order == .earliestRelease {
            Text("Year hints from filenames · unknown years last. Catalogue release dates coming later.").font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 24)
        }
    }

    private func hero(_ video: TelegramVideo) -> some View {
        ZStack(alignment: .bottomLeading) {
            VideoArtwork(video: video)
            LinearGradient(colors: [.black.opacity(0.1), .clear, .black.opacity(0.45), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill").font(.caption)
                    Text(library.snapshot.collections.first(where: { $0.id == video.chatID })?.title ?? "Your library").font(.subheadline.weight(.medium)).lineLimit(1)
                }
                // Keep tracking on Text before View modifiers.
                Text(video.title).tracking(-0.8).font(.largeTitle.weight(.bold)).lineLimit(2)
                HStack(spacing: 10) { Text(video.formatLabel).font(.caption.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6))); Text(ByteCountFormatter.string(fromByteCount: video.size, countStyle: .file)).font(.caption); if video.duration > 0 { Text("\(video.duration / 60) min").font(.caption) } }.foregroundStyle(.white.opacity(0.8))
                if let caption = video.caption, !dynamicTypeSize.isAccessibilitySize { Text(caption).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(2) }
                HStack(spacing: 12) {
                    Button { play(video) } label: {
                        Image(systemName: "play.fill").font(.system(size: 17, weight: .semibold)).offset(x: 1)
                            .frame(width: 44, height: 44).foregroundStyle(.black).background(.white, in: Circle())
                    }.disabled(openingID != nil).accessibilityLabel("Play " + video.title)
                    Text(openingID == video.id ? "Opening…" : (library.snapshot.history[video.id]?.canResume == true ? "Resume" : "Play"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { detailsVideo = video } label: {
                        Image(systemName: "info.circle").font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel("More info about " + video.title)
                }.buttonStyle(CinespicePressStyle())
            }.padding(.horizontal, 24).padding(.bottom, 20)
        }.frame(height: heroHeight).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(.horizontal, 20).contentShape(Rectangle())
    }

    private var personalLibraryPage: some View {
        let saved = library.videos.filter { library.snapshot.savedLists[savedList]?.contains($0.id) == true }
        let items = savedList == "New Releases" ? LibraryOrder.latestRelease.sort(library.videos) : order.sort(saved)
        return VStack(alignment: .leading, spacing: 24) {
            pageTitle("Library", subtitle: "Everything you love, together.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["New Releases", "Favorites", "Watchlist", "History"], id: \.self) { category in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85)) { savedList = category }
                        } label: {
                            Text(category).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .foregroundStyle(savedList == category ? theme.text : theme.muted)
                                .background {
                                    if savedList == category {
                                        Capsule().fill(theme.surface).matchedGeometryEffect(id: "library-category", in: librarySelection)
                                    }
                                }
                        }.buttonStyle(CinespicePressStyle())
                            .accessibilityAddTraits(savedList == category ? .isSelected : [])
                    }
                }.padding(.horizontal, 20)
            }
            if savedList == "History" {
                if library.watchedVideos.isEmpty {
                    LibraryEmptyState(symbol: "clock", title: "Your story starts here", detail: "The videos you watch appear here, with your place saved.")
                } else { grid(Array(library.watchedVideos.prefix(5))) }
            } else {
                HStack {
                    Text("\(items.count) titles").font(.subheadline).foregroundStyle(theme.muted)
                    Spacer()
                    if savedList != "New Releases" { sortControl }
                }.padding(.horizontal, 24)
                if savedList == "New Releases" {
                    Text("From your selected channels · Sorted by filename year")
                        .font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 24)
                } else { releaseSortHint }
                if items.isEmpty {
                    LibraryEmptyState(symbol: savedList == "New Releases" ? "film" : "bookmark",
                                      title: savedList == "New Releases" ? "Make room for your next favorite" : "Save something for later",
                                      detail: savedList == "New Releases" ? "Choose channels to bring their videos into your library." : "Touch and hold a video to add it to Favorites or Watchlist.")
                } else { grid(items) }
            }
        }
    }

    private var downloadsPage: some View {
        let items = order.sort(library.videos.filter { library.display($0).isDownloaded || telegram.fullDownloads.contains($0.fileID) || telegram.preparingDownloads.contains($0.id) })
        return VStack(alignment: .leading, spacing: 16) {
            pageTitle("Downloads", subtitle: "Ready when you are.")
            Text("Touch and hold a video to download or save it to Files.").font(.subheadline).foregroundStyle(theme.muted).padding(.horizontal, 24)
            HStack { Text("\(items.count) titles").font(.caption); Spacer(); sortControl }.padding(.horizontal, 24)
            releaseSortHint
            if items.isEmpty { LibraryEmptyState(symbol: "arrow.down.circle", title: "Take your cinema with you", detail: "Full downloads from selected sources appear here. Partial streaming buffers are not downloads.") }
            else { LazyVStack(spacing: 12) { ForEach(items) { card($0, compact: true) } }.padding(.horizontal, 20) }
        }
    }

    private func collectionPage(_ chat: TelegramChat) -> some View {
        let items = order.sort(browseVideos.filter { $0.chatID == chat.id })
        let cachedIndex = library.snapshot.indexes[chat.id]
        return VStack(alignment: .leading, spacing: 20) {
            pageTitle(chat.title, subtitle: chat.isOwner == true ? "YOUR CHANNEL" : "YOUR SELECTION")
            HStack {
                Text("\(items.count) cached titles").font(.caption).foregroundStyle(theme.muted)
                Spacer()
                sortControl
            }.padding(.horizontal, 20)
            if order == .oldest { Text("Oldest loaded titles first. Load another page to include earlier uploads.").font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 20) }
            releaseSortHint
            grid(items)
            if let error = telegram.collectionErrors[chat.id] { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 24) }
            if items.isEmpty && !telegram.loadingCollections.contains(chat.id) { LibraryEmptyState(symbol: "film", title: "No cached titles", detail: "Load a page or tap Cinespice to refresh this channel.") }
            if telegram.loadingCollections.contains(chat.id) { ProgressView("Finding more videos…").frame(maxWidth: .infinity).tint(theme.accent) }
            else if cachedIndex == nil || cachedIndex?.hasMore == true {
                Button { telegram.loadChat(chat.id) } label: { Text("Load more videos").frame(minHeight: 44) }.buttonStyle(.bordered).tint(theme.accent).frame(maxWidth: .infinity)

            }
        }
    }

    private var searchPage: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = text.isEmpty ? [] : browseVideos.filter { $0.title.localizedCaseInsensitiveContains(text) || ($0.fileName?.localizedCaseInsensitiveContains(text) == true) }
        let merged = Dictionary((local + (text.isEmpty ? [] : telegram.videoSearchResults).filter { library.snapshot.selected.contains($0.chatID) }).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let results = order.sort(Array(merged.values))
        return VStack(alignment: .leading, spacing: 22) {
            pageTitle("Search", subtitle: "Find your next favorite.")
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(theme.muted); TextField("Video title or filename", text: $query).textInputAutocapitalization(.never); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear search") } }
                .frame(minHeight: 44).padding(.horizontal, 15).padding(.vertical, 4).background(theme.surface, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 24)
            if text.isEmpty { LibraryEmptyState(symbol: "magnifyingglass", title: "What are you in the mood for?", detail: "Search video names and filenames in your selected channels and groups.") }
            else {
                HStack { Text("\(results.count) results").font(.caption); Spacer(); sortControl }.padding(.horizontal, 24)
                releaseSortHint
                grid(results)
                if telegram.isSearchingVideos { ProgressView("Searching Telegram…").frame(maxWidth: .infinity).tint(theme.accent) }
                else if !telegram.videoSearchError.isEmpty {
                    Text(telegram.videoSearchError).font(.caption).foregroundStyle(.orange)
                    Button("Retry search") { Task { await telegram.nextVideoSearchPage() } }
                } else if telegram.hasMoreVideoResults {
                    Button("More results") { Task { await telegram.nextVideoSearchPage() } }

                } else if results.isEmpty && !text.isEmpty { LibraryEmptyState(symbol: "magnifyingglass", title: "No matching videos", detail: "Try a different filename or select more channels and groups.") }
                LibraryPageTrigger(enabled: telegram.hasMoreVideoResults && !telegram.isSearchingVideos && telegram.videoSearchError.isEmpty, revision: String(telegram.videoSearchResults.count), viewportHeight: viewport.height) { Task { await telegram.nextVideoSearchPage() } }
            }
        }
        .task(id: query + library.selectedCollections.map { String($0.id) }.joined(separator: ",")) {
            let searched = query
            await telegram.searchVideos(searched)
            guard !Task.isCancelled, query == searched, !searched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            lastSearchVideo = order.sort(local + telegram.videoSearchResults.filter { library.snapshot.selected.contains($0.chatID) }).first
        }
    }

    private func posterRail(_ videos: [TelegramVideo], wide: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) { ForEach(videos) { video in card(video, wide: wide).frame(width: wide ? min(320, viewport.width * 0.72) : min(posterWidth, viewport.width * 0.7)) } }.padding(.horizontal, 20)
        }
    }
    private func rail(_ title: String, subtitle: String, videos: [TelegramVideo], wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(title, detail: subtitle)
            posterRail(videos, wide: wide)
        }
    }
    private func grid(_ videos: [TelegramVideo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(posterWidth, max(140, viewport.width - 48))), spacing: 18)], alignment: .leading, spacing: 28) {
            ForEach(videos) { video in card(video) }
        }.padding(.horizontal, 24)
    }
    private func card(_ video: TelegramVideo, wide: Bool = false, compact: Bool = false) -> some View {
        VideoCard(video: video, wide: wide, compact: compact, opening: openingID == video.id, play: { play(video, resume: $0) }, download: { rangeServer.stop(); telegram.download(video) }, export: { exportVideo(video) }, info: { detailsVideo = video })
    }
    private func exportVideo(_ video: TelegramVideo) {
        guard !exporting else { return }; exporting = true
        let session = library.sessionID
        Task {
            defer { exporting = false }
            do {
                let current = try await telegram.prepare(video)
                let file = try await VideoExport.prepare(current)
                guard session == library.sessionID else { try? FileManager.default.removeItem(at: file.directory); return }
                exportDirectory = file.directory; exportFile = file
            } catch { playbackError = "Could not export video: \(error.localizedDescription)" }
        }
    }
    private func openCollection(_ chat: TelegramChat) { collection = chat; telegram.ensureChat(chat.id) }
    private func play(_ video: TelegramVideo, resume: Bool = true) {
        guard openingID == nil, selection == nil else { return }
        openingTitle = video.fileName ?? video.title
        withAnimation(.easeOut(duration: 0.15)) { openingID = video.id }
        let session = library.sessionID
        let token = UUID(); openingToken = token
        openTask = Task {
            defer { if openingToken == token { openingID = nil; openTask = nil } }
            do {
                // Persist after presentation: opening one video must not wait for
                // a full library snapshot to be decoded and published.
                let current = try await telegram.prepare(video, persist: false)
                try Task.checkCancellation()
                let url: URL
                if current.isDownloaded, !current.localPath.isEmpty { rangeServer.stop(); url = URL(fileURLWithPath: current.localPath) }
                else { url = try await rangeServer.open(video: current, using: telegram) }
                try Task.checkCancellation()
                guard openingToken == token, library.sessionID == session else { return }
                selection = PlaybackSelection(video: current, url: url, resume: resume)
                Task {
                    guard library.sessionID == session else { return }
                    if !(await library.ingest([current])), library.sessionID == session {
                        library.report("Playback opened, but its metadata could not be saved. " + library.error)
                    }
                }
            } catch is CancellationError { }
            catch { if openingToken == token { playbackError = "\(error.localizedDescription) You can use Download first from the video's menu." } }
        }
    }
    private func cancelOpening() {
        openingToken = UUID()
        openTask?.cancel(); openTask = nil
        openingID = nil
        rangeServer.stop()
    }
    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold)).tracking(-0.8)
            Text(subtitle).font(.subheadline).foregroundStyle(theme.muted)
        }.padding(.horizontal, 24).padding(.top, 20)
    }
    private func sectionTitle(_ title: String, detail: String) -> some View { Text(title).font(.title3.weight(.bold)).padding(.horizontal, 20) }
    private func banner(_ message: String) -> some View { Text(message).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 8) }
    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(0, "Home", "house.fill")
            tabButton(2, "Search", "magnifyingglass")
            tabButton(1, "Library", "square.stack.fill")
            tabButton(3, "Downloads", "arrow.down.circle.fill")
        }.padding(6).frame(maxWidth: 480)
            .modifier(CinespiceDockMaterial())
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 6)
    }
    private func tabButton(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            guard tab != index || collection != nil else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
                tab = index; collection = nil
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: tab == index ? .semibold : .regular))
                    .scaleEffect(tab == index && !reduceMotion ? 1.06 : 1)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }.frame(maxWidth: .infinity, minHeight: 54)
                .background {
                    if tab == index {
                        Capsule().fill(theme.text.opacity(0.1))
                            .overlay(Capsule().strokeBorder(theme.text.opacity(0.08), lineWidth: 0.5))
                            .matchedGeometryEffect(id: "dock-selection", in: dockSelection)
                    }
                }.contentShape(Capsule())
        }.buttonStyle(CinespicePressStyle())
            .accessibilityLabel(title).accessibilityAddTraits(tab == index ? .isSelected : [])
            .foregroundStyle(tab == index ? theme.text : theme.muted).accessibilityValue(tab == index ? "Selected" : "")
    }

    @ViewBuilder private var authentication: some View {
        switch telegram.stage {
        case .credentials: authForm("Your private cinema.", subtitle: "Sign in with Telegram to bring your channels, videos and favorites together.") {
            authButton { telegram.connectUsingBuildCredentials() }
        }
        case .phone: authForm("Welcome to your cinema", subtitle: "Enter the phone number linked to Telegram, including its country calling code.") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Country code").font(.caption).foregroundStyle(theme.muted)
                    TextField("+91", text: $countryCode).keyboardType(.phonePad).accessibilityLabel("Country calling code")
                }.frame(width: 110)
                VStack(alignment: .leading) {
                    Text("Phone number").font(.caption).foregroundStyle(theme.muted)
                    TextField("Phone number", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                }
            }
            authButton { telegram.submitPhone(countryCode: countryCode, number: phone) }
        }
        case .code: authForm("Check Telegram", subtitle: "Enter the code sent by Telegram. It may arrive in your Telegram app rather than by SMS.") {
            TextField("Login code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
            authButton { telegram.submitCode(code) }
            Button("Didn't receive a code? Resend") { telegram.resendCode() }.disabled(telegram.isAuthenticating)
        }
        case .password: authForm("One more step", subtitle: "Enter your Telegram two-step verification password.") { SecureField("Password", text: $password); authButton { telegram.submitPassword(password) } }
        case .email: authForm("Your sign-in email", subtitle: "Telegram requires an email address for this login.") { TextField("Email", text: $email).keyboardType(.emailAddress); authButton { telegram.submitEmail(email) } }
        case .emailCode: authForm("Check your email", subtitle: "Enter the verification code from Telegram.") { TextField("Email code", text: $emailCode).keyboardType(.numberPad); authButton { telegram.submitEmailCode(emailCode) } }
        case .loading: VStack(spacing: 24) { Image(systemName: "play.rectangle.fill").font(.system(size: 48, weight: .medium)); Text("cinespice").font(.title.weight(.bold)).tracking(-0.8); ProgressView("Opening your library…").tint(theme.accent) }
        case let .error(message): authForm("Connection needs attention", subtitle: message) { Button { telegram.resetAuth() } label: { Text("Retry connection").frame(minHeight: 44) }.buttonStyle(CinespiceButtonStyle()).tint(theme.accent) }
        case .ready: EmptyView()
        }
    }
    private func authButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if telegram.isAuthenticating { ProgressView().tint(theme.background) }
                Text(telegram.isAuthenticating ? "Connecting…" : "Continue").font(.headline)
                if !telegram.isAuthenticating { Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)) }
            }.frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(theme.background).background(theme.text, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(CinespicePressStyle()).disabled(telegram.isAuthenticating)
    }
    private func authForm<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                if telegram.stage != .credentials {
                    Button { telegram.restartLogin() } label: {
                        Label("Back to sign in", systemImage: "chevron.left")
                    }.disabled(telegram.isAuthenticating).frame(minHeight: 44)
                }
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 46, weight: .medium)).foregroundStyle(theme.text)
                    .frame(width: 100, height: 100).background(theme.surface, in: RoundedRectangle(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(theme.separator.opacity(0.4), lineWidth: 0.5))
                Text("cinespice").font(.system(size: 26, weight: .bold)).tracking(-0.8).foregroundStyle(theme.text).padding(.bottom, 12)
                Text(title).font(.largeTitle.weight(.bold)).tracking(-0.8)
                Text(subtitle).font(.subheadline).foregroundStyle(theme.muted).lineSpacing(5)
                content().font(.body).textFieldStyle(CinespiceFieldStyle()).textInputAutocapitalization(.never).disableAutocorrection(true)
                if !telegram.status.isEmpty { Text(telegram.status).font(.caption).foregroundStyle(.orange) }
            }.padding(28).padding(.top, 24).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
    }
}
