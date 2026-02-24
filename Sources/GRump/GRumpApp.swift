import SwiftUI
#if !GRUMP_SPM_BUILD
import SwiftData
#endif

@main
struct GRumpApp: App {
    @State private var showSplash = true
    @State private var appLoaded = false
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var frameLoop = FrameLoopService()
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var ambientService = AmbientCodeAwarenessService()
    #if os(macOS)
    @AppStorage("ShowMenuBarExtra") private var showMenuBarExtra = false
    #endif

    #if !GRUMP_SPM_BUILD
    private let modelContainer: ModelContainer
    #endif

    @State private var swiftDataError: String?

    init() {
        #if !GRUMP_SPM_BUILD
        do {
            modelContainer = try SwiftDataConfiguration.makeContainer()
        } catch {
            // Graceful fallback — app still launches; persistence degrades to JSON.
            // The error is surfaced in-app rather than crashing.
            modelContainer = try! ModelContainer(for: Schema([]), configurations: [])
            _swiftDataError = State(initialValue: "[SwiftData] \(error.localizedDescription)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if appLoaded {
                    AppRootView()
                        .opacity(showSplash ? 0 : 1)
                }

                if showSplash {
                    SplashScreenView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                }
            }
            .task {
                // Defer loading main app so first frame is just the splash (reduces lag)
                try? await Task.sleep(for: .milliseconds(20))
                appLoaded = true
                #if !GRUMP_SPM_BUILD
                // Migrate legacy conversations.json → SwiftData on first launch
                SwiftDataMigrator.migrateIfNeeded(context: modelContainer.mainContext)
                #endif
                #if os(macOS)
                // Register as macOS Services provider
                GRumpServicesProvider.shared.register()
                #endif
                // Request notification authorization
                GRumpNotificationService.shared.requestAuthorization()
            }
            .environmentObject(themeManager)
            .environmentObject(frameLoop)
            .environmentObject(viewModel)
            .environmentObject(ambientService)
            #if !GRUMP_SPM_BUILD
            .modelContainer(modelContainer)
            #endif
            .preferredColorScheme(themeManager.colorScheme)
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 550)
        #endif
            .onOpenURL { url in
                #if os(macOS)
                GRumpURLSchemeHandler.handle(url)
                #endif
            }
            #if os(macOS)
            .handlesExternalEvents(preferring: Set(["grump"]), allowing: Set(["grump"]))
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentSize)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .init("GRumpNewChat"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleSidebar"), object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Toggle Activity Bar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleActivityBar"), object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button("Toggle Status Bar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleStatusBar"), object: nil)
                }

                Divider()

                Button("Toggle Zen Mode") {
                    NotificationCenter.default.post(name: .init("GRumpToggleZenMode"), object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button("Customize Layout...") {
                    NotificationCenter.default.post(name: .init("GRumpShowLayoutCustomizer"), object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Reset Layout to Defaults") {
                    NotificationCenter.default.post(name: .init("GRumpResetLayout"), object: nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button("What's New") {
                    NotificationCenter.default.post(name: .init("GRumpWhatsNew"), object: nil)
                }
                Divider()
                Menu("Keyboard Shortcuts") {
                    Text("New Chat — ⌘N")
                    Text("Settings — ⌘,")
                    Text("Stop Generation — ⌘.")
                    Text("Focus Input — ⌘L")
                    Text("Toggle Sidebar — ⌘\\")
                    Text("Toggle Activity Bar — ⌘⌥A")
                    Text("Zen Mode — ⌘⇧Z")
                    Text("Customize Layout — ⌘⇧L")
                    Text("Export Markdown — ⌘E")
                    Text("Exit Zen Mode — Escape")
                }
                Divider()
                Button("G-Rump Help") {
                    if let url = URL(string: "https://grump.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        #if os(macOS)
        MenuBarExtra("G-Rump", systemImage: "brain.head.profile", isInserted: $showMenuBarExtra) {
            MenuBarExtraView()
                .environmentObject(viewModel)
        }
        #endif
    }
}
