import SwiftUI

struct CollectionPicker: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope = 2
    var openCollection: (TelegramChat) -> Void = { _ in }
    @State private var changing: Set<Int64> = []
    @State private var visibleLimit = 30
    @State private var scanning = false
    @State private var scanRevision = 0
    private var collections: [TelegramChat] {
        TelegramChat.ownerFirst(library.snapshot.collections.filter {
            let matches = $0.isCollection && $0.matches(query)
            switch scope {
            case 0: return matches && $0.isOwner == true && $0.isChannel == true
            case 1: return matches && library.snapshot.selected.contains($0.id)
            default: return matches
            }
        })
    }
    var body: some View {
        NavigationView {
            ZStack {
                theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Only your picks.\nOnly your screen.").font(.system(size: 30, weight: .bold)).tracking(-1)
                            Text("Owned channels appear first, oldest Telegram date first. Select the sources you want. Only selected channels and groups load videos.").font(.subheadline).foregroundStyle(theme.muted)
                        }
                        Picker("Channels to display", selection: $scope) {
                            Text("My channels").tag(0); Text("Selected").tag(1); Text("All sources").tag(2)
                        }.pickerStyle(.segmented)
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                            TextField("Search your Telegram channels", text: $query).textInputAutocapitalization(.never).disableAutocorrection(true)
                            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear channel search") }
                        }.frame(minHeight: 44).padding(.horizontal, 14).padding(.vertical, 4).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        if telegram.isSearchingChats { ProgressView("Searching Telegram…").tint(theme.accent) }
                        if collections.isEmpty && !telegram.isSearchingChats {
                            Text("No matching sources yet. Search by name or scan another batch, including archived chats.")
                                .font(.subheadline).foregroundStyle(theme.muted).padding(.vertical, 12)
                        }
                        ForEach(Array(collections.prefix(visibleLimit))) { chat in
                            HStack(spacing: 4) {
                                channel(chat)
                                if library.snapshot.selected.contains(chat.id) {
                                    Button { dismiss(); openCollection(chat) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 48) }
                                        .accessibilityLabel("Browse " + chat.title).disabled(!changing.isEmpty)
                                }
                            }.onAppear { if chat.id == collections.prefix(visibleLimit).last?.id { visibleLimit += 30 } }
                        }
                        if collections.count > visibleLimit { Button("Show 30 more cached results") { visibleLimit += 30 } }
                        Divider().overlay(Color.white.opacity(0.12))
                        Text("\(library.selectedCollections.count) selected · Only selected sources appear in your library").font(.caption).foregroundStyle(theme.muted)
                        if scanning || telegram.isLoadingChats { ProgressView("Finding channels and groups…").tint(theme.accent) }
                        else if telegram.hasMoreChats {
                            Button { scanRevision += 1 } label: { Label("Continue finding sources", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(14).background(theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
                        }
                        Text("Search checks Telegram as well as saved metadata. Scanning alternates main and archived chats. Owned channels appear first. Tap a checkmark to remove a source, or its arrow to browse videos.").font(.caption).foregroundStyle(theme.muted)
                        if !telegram.chatSearchError.isEmpty { Text(telegram.chatSearchError).foregroundStyle(.orange).font(.caption) }
                        if !library.error.isEmpty { Text(library.error).foregroundStyle(.orange).font(.caption) }
                        if !telegram.status.isEmpty { Text(telegram.status).foregroundStyle(.orange).font(.caption) }
                    }.padding(22)
                }.scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Choose channels").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.tint(theme.accent).disabled(!changing.isEmpty) } }
            .task(id: scanRevision) {
                scanning = true
                defer { scanning = false }
                await telegram.discoverCollections()
            }
            .task(id: "\(scope)_\(query)") { await telegram.searchCollections(query, channelsOnly: scope == 0) }
            .onChange(of: scope) { _ in visibleLimit = 30 }
            .onChange(of: query) { _ in visibleLimit = 30 }
        }.foregroundStyle(theme.text).tint(theme.accent).navigationViewStyle(.stack).preferredColorScheme(theme.scheme).buttonStyle(CinespiceButtonStyle())
    }
    private func channel(_ chat: TelegramChat) -> some View {
        let selected = library.snapshot.selected.contains(chat.id)
        return Button {
            guard !changing.contains(chat.id) else { return }
            changing.insert(chat.id)
            Task {
                _ = await library.select(chat, selected: !selected)
                changing.remove(chat.id)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(selected ? theme.accent.opacity(0.15) : theme.surface)
                    Image(systemName: chat.isOwner == true ? "crown.fill" : "play.rectangle").foregroundStyle(selected ? theme.accent : theme.muted)
                }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(chat.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text).lineLimit(2)
                    HStack(spacing: 5) {
                        Text(chat.isOwner == true ? "OWNER" : (chat.isChannel == true ? "CHANNEL" : "GROUP"))
                        if let date = chat.telegramDate, date > 0 { Text("·"); Text(Date(timeIntervalSince1970: Double(date)), style: .date) }
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(theme.muted)
                }
                Spacer()
                if changing.contains(chat.id) { ProgressView() }
                else { Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle").font(.title2).foregroundStyle(selected ? theme.accent : theme.muted) }
            }.padding(12).frame(maxWidth: .infinity).background(theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
        }.buttonStyle(CinespiceButtonStyle()).disabled(changing.contains(chat.id))
            .accessibilityLabel("\(chat.title), \(selected ? "selected" : "not selected")")
    }
}

struct LibrarySettingsView: View {
    @AppStorage("cinespice.theme") private var theme: CinespiceTheme = .ember
    @EnvironmentObject private var telegram: TelegramClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rangeServer: TelegramRangeServer
    @Environment(\.dismiss) private var dismiss
    @State private var mediaBytes: Int64 = 0
    @State private var artworkBytes = 0
    @State private var working = false
    @State private var status = ""
    @State private var confirmation: Action?
    private enum Action: String, Identifiable {
        case media, artwork, history, logout
        var id: String { rawValue }
        var title: String {
            switch self {
            case .media: return "Clear downloaded media?"
            case .artwork: return "Clear cached artwork?"
            case .history: return "Clear watch history?"
            case .logout: return "Sign out of Telegram?"
            }
        }
        var detail: String {
            switch self {
            case .media: return "Removes local downloaded videos and documents. Your Telegram cloud messages, library metadata and watch history stay intact."
            case .artwork: return "Removes locally cached thumbnails. Artwork can download again as you browse."
            case .history: return "Removes saved playback positions on this iPhone. Your collections and videos are kept."
            case .logout: return "Removes saved API credentials and signs out of Telegram. Account-specific local library history remains on this iPhone."
            }
        }
    }
    var body: some View {
        NavigationView {
            List {
                Section("Profile") {
                    Label(telegram.profileName.isEmpty ? "Your account" : telegram.profileName, systemImage: "person.crop.circle")
                    if !telegram.profileUsername.isEmpty { Text("@" + telegram.profileUsername).foregroundStyle(theme.muted) }
                }
                Section("Appearance") {
                    Picker("Color palette", selection: $theme) {
                        ForEach(CinespiceTheme.allCases) { palette in Text(palette.title).tag(palette) }
                    }
                    Text("Two dark and two light palettes. Player always uses a dark cinema surface.").font(.caption).foregroundStyle(theme.muted)
                }
                Section("Requests") {
                    Label("Request a feature · Coming later", systemImage: "bubble.left.and.bubble.right").foregroundStyle(theme.muted)
                }
                Section("On this iPhone") {
                    usage("Downloaded media", bytes: mediaBytes)
                    Button("Clear downloaded media") { confirmation = .media }.disabled(working)
                    usage("Cached artwork", bytes: Int64(artworkBytes))
                    Text("Artwork cache trims itself to 40 MB. It never needs the full video.").font(.caption).foregroundStyle(theme.muted)
                    Button("Clear cached artwork") { confirmation = .artwork }.disabled(working)
                }
                Section("Your library") {
                    Text("\(library.videos.count) indexed videos · \(library.selectedCollections.count) collections")
                    Text("Collections, video metadata and watch history are saved in an account-specific SQLite database on this iPhone.").font(.caption).foregroundStyle(theme.muted)
                    Button("Clear watch history", role: .destructive) { confirmation = .history }.disabled(working)
                }
                Section("Playback") {
                    Text("Playback pauses while away and returns to the same player when you reopen the app. Force-quitting starts a fresh screen; your saved watch progress remains.").font(.caption).foregroundStyle(theme.muted)
                }
                Section("Cinespice") {
                    Text("Created by Masalaots")
                    HStack {
                        Link(destination: URL(string: "https://instagram.com/notmasalaoats")!) { Label("Instagram", systemImage: "camera") }
                        Spacer()
                        Link(destination: URL(string: "https://t.me/notmasalaoats")!) { Label("Telegram", systemImage: "paperplane") }
                    }
                    Text("@notmasalaoats").font(.caption).foregroundStyle(theme.muted)
                }
                Section("Account") {
                    Text("Telegram sessions stay in encrypted local TDLib storage. The database key and API credentials stay in Keychain. Login codes and passwords are not stored by Cinespice.").font(.caption).foregroundStyle(theme.muted)
                    Button("Sign out", role: .destructive) { confirmation = .logout }.disabled(working)
                }
                if working { ProgressView("Working…") }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.orange) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Profile & settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() }.tint(theme.accent) } }
            .task { await refreshUsage() }
            .alert(item: $confirmation) { action in
                Alert(title: Text(action.title), message: Text(action.detail), primaryButton: .destructive(Text(action == .logout ? "Sign out" : "Clear")) { perform(action) }, secondaryButton: .cancel())
            }
        }.foregroundStyle(theme.text).tint(theme.accent).navigationViewStyle(.stack).preferredColorScheme(theme.scheme)
    }
    private func usage(_ title: String, bytes: Int64) -> some View {
        HStack { Text(title); Spacer(); Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).foregroundStyle(theme.muted).font(.caption.monospacedDigit()) }
    }
    private func refreshUsage() async {
        do { mediaBytes = try await telegram.storageBytes(); artworkBytes = try await library.thumbnailBytes() }
        catch { status = "Could not read storage usage: \(error.localizedDescription)" }
    }
    private func perform(_ action: Action) {
        working = true
        Task {
            defer { working = false }
            do {
                switch action {
                case .media: rangeServer.stop(); try await telegram.clearMediaCache()
                case .artwork: try await library.clearThumbnails(); VideoArtwork.clearMemory()
                case .history:
                    guard await library.clearHistory() else { status = library.error; return }
                case .logout: rangeServer.stop(); telegram.logOut(); dismiss(); return
                }
                status = "Done."
                await refreshUsage()
            } catch { status = "Could not complete that action: \(error.localizedDescription)" }
        }
    }
}
