import SwiftUI

struct TelegramLibraryView: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    @AppStorage("cinespice.order") private var order: LibraryOrder = .latestRelease
    @Environment(\.scenePhase) private var scenePhase
    @State private var dailySeed = Int(Date().timeIntervalSince1970 / 86400)
    @State private var savedList = "Favorites"
    @State private var lastSearchVideo: TelegramVideo?
    @State private var refreshMessage = ""
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rangeServer: TelegramRangeServer
    @State private var apiID = ""
    @State private var apiHash = ""
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
            if stage == .ready { apiID = ""; apiHash = "" }
            if stage != .ready {
                cancelOpening()
                showCollections = false; showSettings = false
                lastSearchVideo = nil; tab = 0; selection = nil; exportFile = nil; collection = nil; detailsVideo = nil; query = ""; rangeServer.stop()
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let collection { collectionPage(collection) }
                    else {
                        switch tab {
                        case 1: favoritesPage
                        case 2: searchPage
                        case 3: downloadsPage
                        case 4: historyPage
                        case 5: collectionsPage
                        default: home
                        }
                    }
                    if !library.error.isEmpty { banner(library.error) }
                    if !telegram.status.isEmpty { banner(telegram.status) }
                }.padding(.bottom, 24).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }.coordinateSpace(name: "library-scroll")
                .scrollDismissesKeyboard(.interactively)
                .id("\(tab)_\(collection?.id ?? 0)_\(tab == 1 ? savedList : "")_\(library.sessionID)")
            tabs
        }

        .buttonStyle(CinespiceButtonStyle())
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
                Text("CINESPICE").tracking(-1).font(.system(size: 22, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(theme.accent)
            }.accessibilityLabel("Cinespice, refresh current library")
            Spacer(minLength: 0)
            Button { showCollections = true } label: { Image(systemName: "rectangle.stack").frame(width: 44, height: 44) }.accessibilityLabel("Channels and groups")
            Button { showSettings = true } label: { Image(systemName: "person.crop.circle").frame(width: 44, height: 44) }.accessibilityLabel("Profile and settings")
        }.padding(.horizontal, 16).padding(.vertical, 2).background(.ultraThinMaterial)
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
        VStack(alignment: .leading, spacing: 20) {
            heroCarousel
            if !library.continueWatching.isEmpty { rail("Continue Watching", subtitle: "", videos: Array(library.continueWatching.prefix(12)), wide: true) }
            if !library.selectedCollections.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Your channels").font(.title3.weight(.bold)); Spacer(); Button("Manage") { showCollections = true }.font(.caption.weight(.semibold)).foregroundStyle(theme.muted) }.padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) { ForEach(library.selectedCollections) { channelTile($0).frame(width: 238) } }.padding(.horizontal, 20)
                    }
                }
                ForEach(Array(library.selectedCollections.prefix(4))) { chat in
                    let videos = browseVideos.filter { $0.chatID == chat.id }
                    if !videos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Button { openCollection(chat) } label: { HStack { Text(chat.title).font(.title3.weight(.bold)); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }.foregroundStyle(theme.text).padding(.horizontal, 20).frame(minHeight: 44).contentShape(Rectangle()) }
                            posterRail(Array(videos.prefix(18)), wide: false)
                        }
                    }
                }
            }
            HStack { Text("Your library").font(.title3.bold()); Spacer(); sortControl }.padding(.horizontal, 20)
            releaseSortHint
            if browseVideos.isEmpty { LibraryEmptyState(symbol: "film", title: "Your cinema starts here", detail: "Use the channel icon above to select and open a source. Only your selected sources load videos.") }
            else { grid(browseVideos) }
            if !telegram.loadingCollections.isEmpty { ProgressView("Loading a small page…").frame(maxWidth: .infinity).font(.caption).tint(theme.accent) }
        }
    }

    private func channelTile(_ chat: TelegramChat) -> some View {
        let videos = library.videos.filter { $0.chatID == chat.id }
        return Button { openCollection(chat) } label: {
            ZStack(alignment: .bottomLeading) {
                if let video = videos.first { VideoArtwork(video: video) }
                else { theme.surface; Image(systemName: "play.rectangle").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(theme.muted.opacity(0.45)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    if chat.isOwner == true { Label { Text("YOUR CHANNEL").tracking(1) } icon: { Image(systemName: "crown.fill") }.font(.system(size: 8, weight: .bold)).foregroundStyle(theme.accent) }
                    Text(chat.title).font(.system(size: 16, weight: .bold)).lineLimit(2)
                    HStack(spacing: 4) { Text(videos.isEmpty ? "Loading videos…" : "\(videos.count) saved titles"); Spacer(); Image(systemName: "chevron.right") }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }.padding(14)
            }.frame(height: 142).clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(CinespiceButtonStyle())
    }

    private var collectionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("Your channels", subtitle: "CHOSEN BY YOU")
            if library.selectedCollections.isEmpty { LibraryEmptyState(symbol: "rectangle.stack", title: "Choose your screen", detail: "Use Channels above to select the sources you want.") }
            ForEach(library.selectedCollections) { chat in
                let videos = order.sort(browseVideos.filter { $0.chatID == chat.id })
                VStack(alignment: .leading, spacing: 10) {
                    Button { openCollection(chat) } label: {
                        HStack { Text(chat.title).font(.title3.weight(.bold)).lineLimit(1); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                            .foregroundStyle(theme.text).padding(.horizontal, 20).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    if videos.isEmpty { Text("Loading videos…").font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 20) }
                    else { posterRail(Array(videos.prefix(18)), wide: false) }
                }
            }
            if !telegram.loadingCollections.isEmpty { ProgressView("Loading selected channels…").frame(maxWidth: .infinity).tint(theme.accent) }
        }
    }

    private var heroHeight: CGFloat { min(440, max(290, viewport.height * 0.49)) }
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
            Text(title.uppercased()).font(.caption2.bold()).tracking(1.5).foregroundStyle(theme.accent).padding(.horizontal, 20).padding(.vertical, 8)
            if let video { hero(video) }
            else {
                ZStack {
                    LinearGradient(colors: [theme.accent.opacity(0.2), theme.surface], startPoint: .topTrailing, endPoint: .bottomLeading)
                    LibraryEmptyState(symbol: title.hasPrefix("Trending") ? "sparkles" : "play.rectangle", title: title, detail: empty)
                }.frame(height: heroHeight).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16)
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
                    Text("C").font(.system(size: 22, weight: .black)).foregroundStyle(theme.accent)
                    Text(library.snapshot.collections.first(where: { $0.id == video.chatID })?.title.uppercased() ?? "YOUR LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(2).lineLimit(1)
                }
                // Keep tracking on Text before View modifiers.
                Text(video.title).tracking(-0.9).font(.system(size: 27, weight: .heavy)).lineLimit(2)
                HStack(spacing: 10) { Text(video.formatLabel).font(.system(size: 10, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6))); Text(ByteCountFormatter.string(fromByteCount: video.size, countStyle: .file)).font(.caption); if video.duration > 0 { Text("\(video.duration / 60) min").font(.caption) } }.foregroundStyle(.white.opacity(0.8))
                if let caption = video.caption { Text(caption).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(2) }
                HStack(spacing: 12) {
                    Button { play(video) } label: {
                        Label(openingID == video.id ? "Opening…" : (library.snapshot.history[video.id]?.canResume == true ? "Resume" : "Play"), systemImage: "play.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 13).background(.white, in: RoundedRectangle(cornerRadius: 5))
                    }.disabled(openingID != nil)
                    Button { detailsVideo = video } label: { Label("More info", systemImage: "info.circle").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 5)) }
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
        }.frame(height: heroHeight).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 16).contentShape(Rectangle())
    }

    private var favoritesPage: some View {
        let items = order.sort(library.videos.filter { library.snapshot.savedLists[savedList]?.contains($0.id) == true })
        return VStack(alignment: .leading, spacing: 16) {
            pageTitle("Saved for you", subtitle: "FAVORITES & WATCHLIST")
            Picker("Saved list", selection: $savedList) { Text("Favorites").tag("Favorites"); Text("Watchlist").tag("Watchlist") }.pickerStyle(.segmented).padding(.horizontal, 24)
            HStack { Text("\(items.count) titles").font(.caption); Spacer(); sortControl }.padding(.horizontal, 24)
            releaseSortHint
            if items.isEmpty { LibraryEmptyState(symbol: savedList == "Favorites" ? "heart" : "bookmark", title: "Make it yours", detail: "Open a video's ••• menu to add it here. Saved items from deselected sources stay saved and reappear when selected again.") }
            else { grid(items) }
        }.id(savedList)
    }

    private var downloadsPage: some View {
        let items = order.sort(library.videos.filter { library.display($0).isDownloaded || telegram.fullDownloads.contains($0.fileID) || telegram.preparingDownloads.contains($0.id) })
        return VStack(alignment: .leading, spacing: 16) {
            pageTitle("Downloads", subtitle: "READY FOR YOUR NEXT WATCH")
            Text("Download from any video's ••• menu. Completed downloads offer Save to Files with the original filename. Clear local downloads in Profile → Storage.").font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 24)
            HStack { Text("\(items.count) titles").font(.caption); Spacer(); sortControl }.padding(.horizontal, 24)
            releaseSortHint
            if items.isEmpty { LibraryEmptyState(symbol: "arrow.down.circle", title: "Take your cinema with you", detail: "Full downloads from selected sources appear here. Partial streaming buffers are not downloads.") }
            else { grid(items) }
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
            pageTitle("Find your next watch.", subtitle: "SEARCH SELECTED CHANNELS & GROUPS")
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(theme.muted); TextField("Video title or filename", text: $query).textInputAutocapitalization(.never); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear search") } }
                .frame(minHeight: 44).padding(.horizontal, 15).padding(.vertical, 4).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 24)
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

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle("Your watching history", subtitle: "LAST FIVE WATCHED")
            if library.watchedVideos.isEmpty { LibraryEmptyState(symbol: "clock", title: "The story starts here", detail: "Videos you play appear here. Your place is saved on this iPhone.") }
            else { grid(Array(library.watchedVideos.prefix(5))) }
        }
    }

    private func posterRail(_ videos: [TelegramVideo], wide: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) { ForEach(videos) { video in card(video, wide: wide).frame(width: wide ? min(320, viewport.width * 0.72) : min(190, viewport.width * 0.39)) } }.padding(.horizontal, 20)
        }
    }
    private func rail(_ title: String, subtitle: String, videos: [TelegramVideo], wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(title, detail: subtitle)
            posterRail(videos, wide: wide)
        }
    }
    private func grid(_ videos: [TelegramVideo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], alignment: .leading, spacing: 24) {
            ForEach(videos) { video in card(video) }
        }.padding(.horizontal, 24)
    }
    private func card(_ video: TelegramVideo, wide: Bool = false) -> some View {
        VideoCard(video: video, wide: wide, opening: openingID == video.id, play: { play(video, resume: $0) }, download: { rangeServer.stop(); telegram.download(video) }, export: { exportVideo(video) })
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
    private func eyebrow(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .bold)).tracking(2.3).foregroundStyle(theme.accent) }
    private func pageTitle(_ title: String, subtitle: String) -> some View { VStack(alignment: .leading, spacing: 12) { eyebrow(subtitle); Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.7) }.padding(.horizontal, 24).padding(.top, 16) }
    private func sectionTitle(_ title: String, detail: String) -> some View { Text(title).font(.title3.weight(.bold)).padding(.horizontal, 20) }
    private func banner(_ message: String) -> some View { Text(message).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 8) }
    private var tabs: some View {
        HStack {
            tabButton(0, "Home", "house")
            tabButton(1, "Favorites", "heart")
            tabButton(2, "Search", "magnifyingglass")
            tabButton(3, "Downloads", "arrow.down.circle")
            tabButton(4, "History", "clock")
            tabButton(5, "My channels", "rectangle.stack")
        }.padding(.horizontal, 8).padding(.vertical, 3).background(.ultraThinMaterial)
    }
    private func tabButton(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button { tab = index; collection = nil } label: {
            VStack(spacing: 4) { Image(systemName: symbol).font(.system(size: 18, weight: tab == index ? .semibold : .regular)); Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.72) }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
        }.accessibilityLabel(title).accessibilityAddTraits(tab == index ? .isSelected : [])
            .foregroundStyle(tab == index ? theme.accent : theme.muted).accessibilityValue(tab == index ? "Selected" : "")
    }

    @ViewBuilder private var authentication: some View {
        switch telegram.stage {
        case .credentials: authForm("Your private cinema.", subtitle: "Connect your Telegram account. API credentials and your session stay on this iPhone.") {
            TextField("API ID", text: $apiID).keyboardType(.numberPad)
            SecureField("API hash", text: $apiHash)
            Button { telegram.connect(apiID: apiID, apiHash: apiHash) } label: { Text("Connect Telegram").frame(minHeight: 44) }.buttonStyle(.borderedProminent).tint(theme.accent)
            Text("Get your API ID and hash at my.telegram.org. No backend, subscriptions or analytics.").font(.caption).foregroundStyle(theme.muted)
        }
        case .phone: authForm("Your phone number", subtitle: "Use the number linked to your Telegram account.") { TextField("+1 555 555 5555", text: $phone).keyboardType(.phonePad); authButton { telegram.submitPhone(phone) } }
        case .code: authForm("Check Telegram", subtitle: "Enter the sign-in code sent by Telegram.") { TextField("Login code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode); authButton { telegram.submitCode(code) } }
        case .password: authForm("One more step", subtitle: "Enter your Telegram two-step verification password.") { SecureField("Password", text: $password); authButton { telegram.submitPassword(password) } }
        case .email: authForm("Your sign-in email", subtitle: "Telegram requires an email address for this login.") { TextField("Email", text: $email).keyboardType(.emailAddress); authButton { telegram.submitEmail(email) } }
        case .emailCode: authForm("Check your email", subtitle: "Enter the verification code from Telegram.") { TextField("Email code", text: $emailCode).keyboardType(.numberPad); authButton { telegram.submitEmailCode(emailCode) } }
        case .loading: VStack(spacing: 24) { Text("CINESPICE").font(.system(size: 28, weight: .black, design: .rounded)).tracking(6); ProgressView("Restoring your library…").tint(theme.accent) }
        case let .error(message): authForm("Connection needs attention", subtitle: message) { Button { telegram.resetAuth() } label: { Text("Back to sign in").frame(minHeight: 44) }.buttonStyle(CinespiceButtonStyle()).tint(theme.accent) }
        case .ready: EmptyView()
        }
    }
    private func authButton(_ action: @escaping () -> Void) -> some View { Button(action: action) {
        HStack { if telegram.isAuthenticating { ProgressView() }; Text(telegram.isAuthenticating ? "Checking…" : "Continue") }.frame(minHeight: 44)
    }.buttonStyle(.borderedProminent).tint(theme.accent).disabled(telegram.isAuthenticating) }
    private func authForm<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Text("CINESPICE").font(.system(size: 22, weight: .black, design: .rounded)).tracking(5).foregroundStyle(theme.accent).padding(.bottom, 48)
                Text(title).font(.system(size: 38, weight: .medium, design: .serif)).tracking(-1)
                Text(subtitle).font(.subheadline).foregroundStyle(theme.muted).lineSpacing(5)
                content().textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).disableAutocorrection(true)
                if !telegram.status.isEmpty { Text(telegram.status).font(.caption).foregroundStyle(.orange) }
            }.padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
    }
}
