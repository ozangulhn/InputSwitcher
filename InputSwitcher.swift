import Cocoa
import Carbon
import Foundation
import Network

// MARK: - Models

struct InputSource {
    let name: String
    let value: Int
    let icon: String
    let nickname: String
    let includeInShortcutCycle: Bool
    let commandMode: InputCommandMode

    var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var menuLabel: String {
        trimmedNickname.isEmpty ? name : "\(name) • \(trimmedNickname)"
    }
}

struct ShortcutConfig {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        parts.append(keyName(for: keyCode))
        return parts.joined()
    }
}

struct InputRowControls {
    let nameField: NSTextField
    let nicknameField: NSTextField
    let valueField: NSTextField
    let commandModePopup: NSPopUpButton
    let testButton: NSButton
    let shortcutToggle: NSButton
}

struct DisplayOption {
    let index: Int
    let title: String
}

enum InputCommandMode: String, CaseIterable {
    case auto = "auto"
    case standard = "standard"
    case lgAlternate = "lgAlternate"

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .standard:
            return "input"
        case .lgAlternate:
            return "input-alt (LG)"
        }
    }

    var commandName: String {
        switch self {
        case .auto, .standard:
            return "input"
        case .lgAlternate:
            return "input-alt"
        }
    }
}

struct ShellResult {
    let status: Int32
    let output: String
}

struct DiscoveryProbe {
    let label: String
    let source: InputSource
}

// MARK: - Diagnostics

extension Notification.Name {
    static let diagnosticsLogDidChange = Notification.Name("DiagnosticsLogDidChange")
}

class DiagnosticsLogStore {
    static let shared = DiagnosticsLogStore()

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let lock = NSLock()
    private var storedEntries: [String] = []
    let maxEntries = 400

    var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    func append(_ message: String) {
        lock.lock()
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)"
        storedEntries.append(line)
        if storedEntries.count > maxEntries {
            storedEntries.removeFirst(storedEntries.count - maxEntries)
        }
        lock.unlock()
        notifyChange()
    }

    func joinedText() -> String {
        entries.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        storedEntries.removeAll()
        lock.unlock()
        notifyChange()
    }

    private func notifyChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .diagnosticsLogDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .diagnosticsLogDidChange, object: nil)
            }
        }
    }
}

func logDiagnostics(_ message: String) {
    DiagnosticsLogStore.shared.append(message)
}

// MARK: - Shortcut Helpers

func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0

    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    if flags.contains(.option) { carbon |= UInt32(optionKey) }
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

    return carbon
}

func keyName(for keyCode: UInt32) -> String {
    let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`", 65: ".", 67: "*", 69: "+",
        71: "Clear", 75: "/", 76: "Return", 78: "-", 81: "=", 82: "0",
        83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
        91: "8", 92: "9", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "Page Up", 117: "Delete", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "Left", 124: "Right",
        125: "Down", 126: "Up"
    ]

    return names[keyCode] ?? "Key \(keyCode)"
}

func isModifierKey(_ keyCode: UInt16) -> Bool {
    [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(Int(keyCode))
}

func appVersionString() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
}

func localMachineName() -> String {
    Host.current().localizedName ?? ProcessInfo.processInfo.hostName
}

func normalizedDisplayIdentity(_ title: String?) -> String? {
    guard let title else { return nil }

    let base = title.components(separatedBy: " (").first ?? title
    let normalized = base
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    return normalized.isEmpty ? nil : normalized
}

struct PeerMessage: Codable {
    let type: String
    let senderID: String
    let senderName: String
    let displayTitle: String?
    let displayIdentity: String?
    let isDisplayLocal: Bool?
    let requestedInputValue: Int?
}

protocol PeerManagerDelegate: AnyObject {
    func peerManager(_ manager: PeerManager, didReceive message: PeerMessage)
}

class PeerManager {
    weak var delegate: PeerManagerDelegate?

    let instanceID: String
    let instanceName: String
    let serviceType = "_inputswitcher._tcp"
    let queue = DispatchQueue(label: "InputSwitcher.PeerManager")

    var listener: NWListener?
    var browser: NWBrowser?
    private let peersLock = NSLock()
    private var storedPeers: [String: NWEndpoint] = [:]

    var peers: [String: NWEndpoint] {
        get {
            peersLock.lock()
            defer { peersLock.unlock() }
            return storedPeers
        }
        set {
            peersLock.lock()
            storedPeers = newValue
            peersLock.unlock()
        }
    }
    var registeredServiceName: String?

    init(instanceID: String, instanceName: String) {
        self.instanceID = instanceID
        self.instanceName = instanceName
    }

    func start() {
        logDiagnostics("PeerManager start: instance=\(instanceName) id=\(instanceID)")
        startListener()
        startBrowser()
    }

    func startListener() {
        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters, on: .any)
            var txtRecord = NWTXTRecord()
            txtRecord["id"] = instanceID
            listener.service = NWListener.Service(name: instanceName, type: serviceType, domain: nil, txtRecord: txtRecord)
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                guard let self else { return }
                if case .add(let endpoint) = change, case .service(let name, _, _, _) = endpoint {
                    self.registeredServiceName = name
                    logDiagnostics("Peer service registered: name=\(name)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            logDiagnostics("Peer listener active: service=\(serviceType) name=\(instanceName)")
        } catch {
            logDiagnostics("Peer listener failed: \(error.localizedDescription)")
            print("Peer listener failed: \(error)")
        }
    }

    func startBrowser() {
        let parameters = NWParameters.tcp
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var updatedPeers: [String: NWEndpoint] = [:]

            for result in results {
                if self.isSelf(result) {
                    continue
                }
                let endpointKey = self.endpointKey(for: result.endpoint)
                updatedPeers[endpointKey] = result.endpoint
            }

            self.peers = updatedPeers
            let peerNames = updatedPeers.keys.sorted().joined(separator: ", ")
            logDiagnostics("Peer browser update: count=\(updatedPeers.count) peers=[\(peerNames)]")
        }
        browser.start(queue: queue)
        self.browser = browser
        logDiagnostics("Peer browser active: service=\(serviceType)")
    }

    func isSelf(_ result: NWBrowser.Result) -> Bool {
        if case .bonjour(let txtRecord) = result.metadata,
           let peerID = txtRecord["id"],
           peerID == instanceID {
            return true
        }

        if case .service(let name, _, _, _) = result.endpoint {
            return name == (registeredServiceName ?? instanceName)
        }

        return false
    }

    func endpointKey(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        default:
            return endpoint.debugDescription
        }
    }

    func handle(connection: NWConnection) {
        logDiagnostics("Peer connection accepted")
        connection.start(queue: queue)
        receiveMessage(on: connection, buffer: Data())
    }

    func receiveMessage(on connection: NWConnection, buffer: Data) {
        let maxMessageSize = 64 * 1024
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxMessageSize) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if accumulated.count > maxMessageSize {
                logDiagnostics("Peer message dropped: exceeds \(maxMessageSize) bytes")
                connection.cancel()
                return
            }

            if error == nil, !isComplete {
                self.receiveMessage(on: connection, buffer: accumulated)
                return
            }

            connection.cancel()
            self.process(accumulated, receiveError: error)
        }
    }

    func process(_ data: Data, receiveError: NWError?) {
        if let receiveError {
            logDiagnostics("Peer receive error: \(receiveError.localizedDescription)")
        }

        guard !data.isEmpty else { return }

        do {
            let message = try JSONDecoder().decode(PeerMessage.self, from: data)

            if message.senderID == self.instanceID {
                logDiagnostics("Peer message ignored: echoed from self")
                return
            }

            logDiagnostics("Peer message received: type=\(message.type) from=\(message.senderName) identity=\(message.displayIdentity ?? "-") input=\(message.requestedInputValue.map(String.init) ?? "-") local=\(message.isDisplayLocal.map(String.init) ?? "-")")

            DispatchQueue.main.async {
                self.delegate?.peerManager(self, didReceive: message)
            }
        } catch {
            logDiagnostics("Peer message decode failed: bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func send(_ message: PeerMessage, to endpoint: NWEndpoint) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        logDiagnostics("Peer message send: type=\(message.type) to=\(endpointKey(for: endpoint)) identity=\(message.displayIdentity ?? "-") input=\(message.requestedInputValue.map(String.init) ?? "-")")

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: queue)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func broadcast(_ message: PeerMessage) {
        for endpoint in peers.values {
            send(message, to: endpoint)
        }
    }

    func hasPeers() -> Bool {
        !peers.isEmpty
    }
}

// MARK: - DDC Controller

class DDCController {
    static let candidatePaths = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc"
    ]

    static let legacyLGAlternateMap: [Int: Int] = [
        15: 208,
        16: 209,
        17: 144,
        18: 145,
        27: 210
    ]

    static func setInput(_ source: InputSource, displayIndex: Int = 1, displayTitle: String? = nil) -> ShellResult {
        guard let m1ddcPath = resolvedM1ddcPath() else {
            logDiagnostics("DDC setInput failed: m1ddc missing")
            return ShellResult(status: 1, output: "m1ddc bulunamadı. Homebrew yolu veya PATH kontrol edilmeli.")
        }
        let resolvedMode = resolvedCommandMode(source.commandMode, displayTitle: displayTitle)
        let commandName = resolvedMode.commandName
        let resolvedValue = resolvedDDCValue(for: source.value, mode: source.commandMode, displayTitle: displayTitle)
        let command = "\(m1ddcPath) display \(displayIndex) set \(commandName) \(resolvedValue)"
        logDiagnostics("DDC setInput: display=\(displayIndex) mode=\(resolvedMode.rawValue) requested=\(source.value) resolved=\(resolvedValue)")
        return run(command)
    }

    static func getCurrentInput(displayIndex: Int = 1) -> Int? {
        guard let m1ddcPath = resolvedM1ddcPath() else { return nil }
        let result = run("\(m1ddcPath) display \(displayIndex) get input")
        guard result.status == 0 else { return nil }
        logDiagnostics("DDC getCurrentInput: display=\(displayIndex) output=\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func listDisplays() -> String {
        guard let m1ddcPath = resolvedM1ddcPath() else { return "" }
        return run("\(m1ddcPath) display list").output
    }

    static func availableDisplays() -> [DisplayOption] {
        let lines = listDisplays()
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsed = lines.compactMap { line -> DisplayOption? in
            guard line.first == "[",
                  let bracketIndex = line.firstIndex(of: "]"),
                  let index = Int(line[line.index(after: line.startIndex)..<bracketIndex]) else {
                return nil
            }

            let titleStart = line.index(after: bracketIndex)
            let title = line[titleStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            return DisplayOption(index: index, title: title.isEmpty ? "Display \(index)" : title)
        }

        if !parsed.isEmpty {
            return parsed
        }

        return []
    }

    static func resolvedCommandMode(_ mode: InputCommandMode, displayTitle: String?) -> InputCommandMode {
        guard mode == .auto else { return mode }
        let normalizedTitle = (displayTitle ?? "").lowercased()
        return normalizedTitle.contains("lg") ? .lgAlternate : .standard
    }

    static func resolvedDDCValue(for value: Int, mode: InputCommandMode, displayTitle: String?) -> Int {
        let resolvedMode = resolvedCommandMode(mode, displayTitle: displayTitle)
        if mode == .auto, resolvedMode == .lgAlternate {
            return legacyLGAlternateMap[value] ?? value
        }
        return value
    }

    static func run(_ command: String) -> ShellResult {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = ShellResult(
            status: task.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
        if result.status != 0 || command.contains(" set ") {
            let compactOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            logDiagnostics("Shell result: status=\(result.status) command=\(command) output=\(compactOutput.isEmpty ? "-" : compactOutput)")
        }
        return result
    }

    static func isM1ddcAvailable() -> Bool {
        resolvedM1ddcPath() != nil
    }

    private static let pathLock = NSLock()
    private static var cachedM1ddcPath: String?
    private static var lastFailedResolution: Date?
    private static var lastResolutionFailed = false
    private static let resolutionRetryInterval: TimeInterval = 10

    static func resolvedM1ddcPath() -> String? {
        pathLock.lock()
        defer { pathLock.unlock() }

        let fileManager = FileManager.default

        if let cachedM1ddcPath {
            if fileManager.isExecutableFile(atPath: cachedM1ddcPath) {
                return cachedM1ddcPath
            }
            self.cachedM1ddcPath = nil
        }

        if let lastFailedResolution, Date().timeIntervalSince(lastFailedResolution) < resolutionRetryInterval {
            return nil
        }

        var resolved: String?
        var source = ""

        if let candidate = candidatePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            resolved = candidate
            source = "candidate path"
        } else {
            let whichResult = run("/usr/bin/which m1ddc")
            let path = whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if whichResult.status == 0, !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
                resolved = path
                source = "PATH"
            }
        }

        if let resolved {
            logDiagnostics("m1ddc resolved via \(source): \(resolved)")
            cachedM1ddcPath = resolved
            lastFailedResolution = nil
            lastResolutionFailed = false
            return resolved
        }

        if !lastResolutionFailed {
            logDiagnostics("m1ddc resolution failed")
            lastResolutionFailed = true
        }
        lastFailedResolution = Date()
        return nil
    }
}

// MARK: - Settings Delegate

protocol SettingsDelegate: AnyObject {
    func didSaveSettings(inputs: [InputSource], shortcutConfig: ShortcutConfig?, displayIndex: Int, displayTitle: String)
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var currentInputValue: Int?
    var lastSelectedInputValue: Int?
    var shortcutConfig: ShortcutConfig?
    var selectedDisplayIndex = 1
    var selectedDisplayTitleValue: String?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandlerRef: EventHandlerRef?
    var settingsWindowController: SettingsWindowController?
    var aboutWindowController: AboutWindowController?
    var diagnosticsWindowController: DiagnosticsWindowController?
    var peerManager: PeerManager?
    var monitorStatusTimer: Timer?
    var knownMonitorOwnerName: String?
    var instanceID: String = UUID().uuidString
    let instanceName = localMachineName()
    var lastKnownLocalPresence: Bool?
    var cachedDisplays: [DisplayOption] = []
    var displayCacheCompletions: [() -> Void] = []
    var isRefreshingDisplayCache = false

    let hotKeyID = EventHotKeyID(signature: fourCharCode("ISWT"), id: 1)

    var inputs: [InputSource] = [
        InputSource(name: "DisplayPort 1", value: 15, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .auto),
        InputSource(name: "DisplayPort 2", value: 16, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .auto),
        InputSource(name: "HDMI 1", value: 17, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .auto),
        InputSource(name: "HDMI 2", value: 18, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .auto),
        InputSource(name: "USB-C", value: 27, icon: "cable.connector", nickname: "", includeInShortcutCycle: false, commandMode: .auto)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let savedInputs = loadInputs() {
            inputs = savedInputs
        }

        lastSelectedInputValue = loadLastSelectedInput()
        shortcutConfig = loadShortcutConfig()
        selectedDisplayIndex = loadSelectedDisplayIndex()
        selectedDisplayTitleValue = loadSelectedDisplayTitle()
        instanceID = loadOrCreateInstanceID()
        logDiagnostics("App launch: name=\(instanceName) version=\(appVersionString()) displayTitle=\(selectedDisplayTitleValue ?? "-") displayIndex=\(selectedDisplayIndex)")

        setupStatusItem()
        installHotKeyHandlerIfNeeded()
        registerGlobalShortcut()
        peerManager = PeerManager(instanceID: instanceID, instanceName: instanceName)
        peerManager?.delegate = self
        peerManager?.start()
        startMonitorStatusTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        buildMenu()
        refreshDisplayCache { [weak self] in
            guard let self else { return }
            self.refreshCurrentInput()
            self.refreshMonitorLocation(forceBroadcast: true)
            self.requestPeerStatus()
        }
    }

    @objc func screenParametersDidChange() {
        refreshDisplayCache { [weak self] in
            self?.refreshMonitorLocation(forceBroadcast: false)
        }
    }

    func refreshDisplayCache(completion: (() -> Void)? = nil) {
        if let completion {
            displayCacheCompletions.append(completion)
        }
        guard !isRefreshingDisplayCache else { return }
        isRefreshingDisplayCache = true

        DispatchQueue.global(qos: .utility).async {
            let displays = DDCController.availableDisplays()
            DispatchQueue.main.async {
                self.cachedDisplays = displays
                self.isRefreshingDisplayCache = false
                let completions = self.displayCacheCompletions
                self.displayCacheCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Input Switcher")
            button.image?.isTemplate = true
            button.toolTip = "Input Switcher"
        }
    }

    func buildMenu() {
        menu = NSMenu()
        menu.minimumWidth = 260

        let titleItem = NSMenuItem()
        titleItem.view = makeHeaderView()
        menu.addItem(titleItem)

        menu.addItem(.separator())

        if !DDCController.isM1ddcAvailable() {
            let warnItem = NSMenuItem(title: "⚠️  m1ddc bulunamadı", action: nil, keyEquivalent: "")
            warnItem.isEnabled = false
            menu.addItem(warnItem)

            let installItem = NSMenuItem(title: "Kurulum talimatlarını göster", action: #selector(showInstallInstructions), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)

            menu.addItem(.separator())
        } else {
            let sectionLabel = NSMenuItem(title: "INPUT KAYNAĞINI SEÇ", action: nil, keyEquivalent: "")
            sectionLabel.isEnabled = false
            sectionLabel.attributedTitle = NSAttributedString(
                string: "INPUT KAYNAĞINI SEÇ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(sectionLabel)

            let displayName = selectedDisplayTitle() ?? "Monitör \(selectedDisplayIndex)"
            let displayLabel = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
            displayLabel.isEnabled = false
            displayLabel.attributedTitle = NSAttributedString(
                string: displayName,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(displayLabel)

            let locationItem = NSMenuItem(title: monitorLocationText(), action: nil, keyEquivalent: "")
            locationItem.isEnabled = false
            locationItem.attributedTitle = NSAttributedString(
                string: monitorLocationText(),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(locationItem)

            for source in inputs {
                menu.addItem(makeInputMenuItem(source: source))
            }

            menu.addItem(.separator())

            let cycleItem = NSMenuItem(title: cycleMenuTitle(), action: #selector(cycleShortcutInputsFromMenu), keyEquivalent: "")
            cycleItem.target = self
            cycleItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: nil)
            cycleItem.isEnabled = !shortcutCycleSources().isEmpty
            menu.addItem(cycleItem)

            let refreshItem = NSMenuItem(title: "Mevcut Input'u Yenile", action: #selector(refreshCurrentInput), keyEquivalent: "r")
            refreshItem.target = self
            refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            menu.addItem(refreshItem)

            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: "Input Listesini Düzenle...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "Hakkında", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let diagnosticsItem = NSMenuItem(title: "Tanılama Günlüğü", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        diagnosticsItem.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func makeHeaderView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))

        let icon = NSImageView(frame: NSRect(x: 16, y: 14, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        container.addSubview(icon)

        let label = NSTextField(frame: NSRect(x: 48, y: 24, width: 200, height: 18))
        label.stringValue = "Input Switcher"
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.backgroundColor = .clear
        container.addSubview(label)

        let sublabel = NSTextField(frame: NSRect(x: 48, y: 8, width: 200, height: 14))
        sublabel.font = NSFont.systemFont(ofSize: 10)
        sublabel.isBezeled = false
        sublabel.isEditable = false
        sublabel.backgroundColor = .clear

        if let currentSource = displayedCurrentSource() {
            let prefix = isResolvedFromDetectedInput(currentSource) ? "Aktif" : "Son seçilen"
            sublabel.stringValue = "\(prefix): \(currentSource.menuLabel)"
            sublabel.textColor = .controlAccentColor
        } else if let currentInputValue {
            sublabel.stringValue = "Aktif: Input \(currentInputValue)"
            sublabel.textColor = .secondaryLabelColor
        } else {
            sublabel.stringValue = "Aktif input bilinmiyor"
            sublabel.textColor = .secondaryLabelColor
        }

        container.addSubview(sublabel)
        return container
    }

    func makeInputMenuItem(source: InputSource) -> NSMenuItem {
        let isCurrent = displayedCurrentSource()?.value == source.value
        let item = NSMenuItem(title: source.menuLabel, action: #selector(switchInput(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = source.value
        item.image = NSImage(systemSymbolName: source.icon, accessibilityDescription: nil)
        item.state = isCurrent ? .on : .off
        item.onStateImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        item.attributedTitle = attributedTitle(for: source, isCurrent: isCurrent)
        item.toolTip = source.trimmedNickname.isEmpty ? source.name : "\(source.name) - \(source.trimmedNickname)"
        return item
    }

    func attributedTitle(for source: InputSource, isCurrent: Bool) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: source.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isCurrent ? .semibold : .regular),
                .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.labelColor
            ]
        )

        if !source.trimmedNickname.isEmpty {
            title.append(
                NSAttributedString(
                    string: "  •  ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                    ]
                )
            )
            title.append(
                NSAttributedString(
                    string: source.trimmedNickname,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                    ]
                )
            )
        }

        return title
    }

    func displayedCurrentSource() -> InputSource? {
        if let currentInputValue,
           let detectedSource = inputs.first(where: { $0.value == currentInputValue }) {
            return detectedSource
        }

        if let lastSelectedInputValue,
           let fallbackSource = inputs.first(where: { $0.value == lastSelectedInputValue }) {
            return fallbackSource
        }

        return nil
    }

    func isResolvedFromDetectedInput(_ source: InputSource) -> Bool {
        currentInputValue == source.value
    }

    func cycleMenuTitle() -> String {
        guard !shortcutCycleSources().isEmpty else {
            return "Kısayol için input seç"
        }

        if let shortcutConfig {
            return "Seçili inputlar arasında geç (\(shortcutConfig.displayString))"
        }

        return "Seçili inputlar arasında geç"
    }

    func shortcutCycleSources() -> [InputSource] {
        inputs.filter { $0.includeInShortcutCycle }
    }

    func switchToInputValue(_ value: Int) {
        guard DDCController.isM1ddcAvailable() else { return }
        guard let source = inputs.first(where: { $0.value == value }) else { return }
        logDiagnostics("Switch requested: input=\(value) mode=\(source.commandMode.rawValue) label=\(source.menuLabel) localDisplay=\(currentDisplayIndex().map(String.init) ?? "-") selectedDisplay=\(selectedDisplayTitle() ?? "-")")

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
            button.image?.isTemplate = true
        }

        let savedTitle = selectedDisplayTitleValue
        let savedIndex = selectedDisplayIndex

        DispatchQueue.global(qos: .userInitiated).async {
            let displays = DDCController.availableDisplays()
            let display = AppDelegate.matchDisplay(in: displays, title: savedTitle, index: savedIndex)

            guard let display else {
                DispatchQueue.main.async {
                    self.cachedDisplays = displays
                    self.restoreStatusIcon()
                    logDiagnostics("Switch rerouted: selected display not local on \(self.instanceName)")
                    self.handleLocalSwitchFailure(
                        targetInputValue: value,
                        commandOutput: "Seçili monitör bu Mac'te bağlı görünmüyor."
                    )
                }
                return
            }

            let displayIndex = display.index
            let commandResult = DDCController.setInput(
                source,
                displayIndex: displayIndex,
                displayTitle: display.title
            )
            guard commandResult.status == 0 else {
                DispatchQueue.main.async {
                    self.restoreStatusIcon()
                    logDiagnostics("Switch local command failed: input=\(value) status=\(commandResult.status)")
                    self.handleLocalSwitchFailure(targetInputValue: value, commandOutput: commandResult.output)
                }
                return
            }

            Thread.sleep(forTimeInterval: 1.0)
            let detectedValue = DDCController.getCurrentInput(displayIndex: displayIndex)

            DispatchQueue.main.async {
                self.cachedDisplays = displays
                self.currentInputValue = detectedValue
                self.lastSelectedInputValue = value
                self.saveLastSelectedInput(value)
                self.buildMenu()
                self.refreshMonitorLocation(forceBroadcast: true)
                logDiagnostics("Switch local command succeeded: input=\(value) detected=\(detectedValue.map(String.init) ?? "-")")

                self.restoreStatusIcon()

                let inputName = self.inputs.first(where: { $0.value == value })?.menuLabel ?? "Input \(value)"
                self.showNotification(inputName: inputName)
            }
        }
    }

    func triggerShortcutCycle() {
        let cycleSources = shortcutCycleSources()
        guard !cycleSources.isEmpty else {
            NSSound.beep()
            return
        }

        let currentValue = displayedCurrentSource()?.value
        let nextValue: Int

        if let currentValue,
           let currentIndex = cycleSources.firstIndex(where: { $0.value == currentValue }) {
            nextValue = cycleSources[(currentIndex + 1) % cycleSources.count].value
        } else {
            nextValue = cycleSources[0].value
        }

        switchToInputValue(nextValue)
    }

    func startMonitorStatusTimer() {
        monitorStatusTimer?.invalidate()
        monitorStatusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshDisplayCache {
                self?.refreshMonitorLocation(forceBroadcast: false)
                self?.requestPeerStatus()
            }
        }
    }

    func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.signature == appDelegate.hotKeyID.signature && hotKeyID.id == appDelegate.hotKeyID.id {
                    DispatchQueue.main.async {
                        appDelegate.triggerShortcutCycle()
                    }
                }

                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &hotKeyHandlerRef
        )
    }

    func registerGlobalShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        guard let shortcutConfig else { return }

        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcutConfig.keyCode,
            shortcutConfig.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        if status == noErr {
            hotKeyRef = registeredHotKey
        }
    }

    // MARK: - Actions

    @objc func switchInput(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        switchToInputValue(value)
    }

    @objc func cycleShortcutInputsFromMenu() {
        triggerShortcutCycle()
    }

    @objc func refreshCurrentInput() {
        let savedTitle = selectedDisplayTitleValue
        let savedIndex = selectedDisplayIndex

        DispatchQueue.global(qos: .background).async {
            logDiagnostics("Refresh current input requested")
            let displays = DDCController.availableDisplays()
            let displayIndex = AppDelegate.matchDisplay(in: displays, title: savedTitle, index: savedIndex)?.index ?? savedIndex
            let current = DDCController.getCurrentInput(displayIndex: displayIndex)
            DispatchQueue.main.async {
                self.cachedDisplays = displays
                self.currentInputValue = current
                logDiagnostics("Refresh current input result: \(current.map(String.init) ?? "-")")
                self.buildMenu()
            }
        }
    }

    @objc func showInstallInstructions() {
        let alert = NSAlert()
        alert.messageText = "m1ddc Kurulumu"
        alert.informativeText = """
        m1ddc'yi kurmak için Terminal'de şunu çalıştırın:

        git clone https://github.com/waydabber/m1ddc
        cd m1ddc
        make
        sudo cp m1ddc /usr/local/bin/

        Kurulumdan sonra bu uygulamayı yeniden başlatın.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "Komutu Kopyala")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let command = "git clone https://github.com/waydabber/m1ddc && cd m1ddc && make && sudo cp m1ddc /usr/local/bin/"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    @objc func openSettings() {
        settingsWindowController?.close()
        let availableDisplays = DDCController.availableDisplays()
        let settingsDisplays: [DisplayOption]
        if availableDisplays.isEmpty, let savedTitle = selectedDisplayTitleValue {
            settingsDisplays = [DisplayOption(index: selectedDisplayIndex, title: savedTitle)]
        } else {
            settingsDisplays = availableDisplays
        }

        settingsWindowController = SettingsWindowController(
            inputs: inputs,
            shortcutConfig: shortcutConfig,
            selectedDisplayIndex: selectedDisplayIndex,
            selectedDisplayTitle: selectedDisplayTitle(),
            displays: settingsDisplays
        )
        settingsWindowController?.delegate = self
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }

        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showDiagnostics() {
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController()
        }

        diagnosticsWindowController?.showWindow(nil)
        diagnosticsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showNotification(inputName: String) {
        statusItem.button?.toolTip = "Aktif: \(inputName)"
    }

    func restoreStatusIcon() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
            button.image?.isTemplate = true
        }
    }

    func showCommandError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    func selectedDisplayTitle() -> String? {
        currentDisplayOption()?.title ?? selectedDisplayTitleValue
    }

    func currentDisplayOption() -> DisplayOption? {
        AppDelegate.matchDisplay(in: cachedDisplays, title: selectedDisplayTitleValue, index: selectedDisplayIndex)
    }

    static func matchDisplay(in displays: [DisplayOption], title: String?, index: Int) -> DisplayOption? {
        if let title,
           let display = displays.first(where: { $0.title == title }) {
            return display
        }

        return displays.first(where: { $0.index == index })
    }

    func currentDisplayIndex() -> Int? {
        currentDisplayOption()?.index
    }

    func handleLocalSwitchFailure(targetInputValue: Int, commandOutput: String) {
        let trimmedOutput = commandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        logDiagnostics("Handle local switch failure: input=\(targetInputValue) output=\(trimmedOutput.isEmpty ? "-" : trimmedOutput)")
        if trimmedOutput.localizedCaseInsensitiveContains("display does not exist") ||
            trimmedOutput.localizedCaseInsensitiveContains("bağlı görünmüyor") {
            requestRemoteSwitch(targetInputValue: targetInputValue)
            return
        }

        showCommandError(
            title: "Input değiştirilemedi",
            message: trimmedOutput.isEmpty ? "m1ddc komutu başarısız oldu." : trimmedOutput
        )
    }

    func refreshMonitorLocation(forceBroadcast: Bool) {
        let isLocal = currentDisplayOption() != nil
        let previousOwnerName = knownMonitorOwnerName

        if isLocal {
            knownMonitorOwnerName = instanceName
        }

        if forceBroadcast || lastKnownLocalPresence != isLocal || previousOwnerName != knownMonitorOwnerName {
            logDiagnostics("Refresh monitor location: isLocal=\(isLocal) selectedDisplay=\(selectedDisplayTitle() ?? "-") owner=\(knownMonitorOwnerName ?? "-") force=\(forceBroadcast)")
        }

        if forceBroadcast || lastKnownLocalPresence != isLocal {
            lastKnownLocalPresence = isLocal
            buildMenu()

            if let selectedDisplayTitle = selectedDisplayTitle() {
                peerManager?.broadcast(
                    PeerMessage(
                        type: "status",
                        senderID: instanceID,
                        senderName: instanceName,
                        displayTitle: selectedDisplayTitle,
                        displayIdentity: normalizedDisplayIdentity(selectedDisplayTitle),
                        isDisplayLocal: isLocal,
                        requestedInputValue: nil
                    )
                )
            }
        }
    }

    func monitorLocationText() -> String {
        if currentDisplayOption() != nil {
            return "Monitör: Bu Mac"
        }

        if let knownMonitorOwnerName {
            return "Monitör: \(knownMonitorOwnerName)"
        }

        return "Monitör: Ağda aranıyor"
    }

    func requestRemoteSwitch(targetInputValue: Int) {
        guard let selectedDisplayTitle = selectedDisplayTitle() else {
            logDiagnostics("Remote switch aborted: no selected display title")
            showCommandError(title: "Uzak geçiş yapılamadı", message: "Önce hedef monitörü seç.")
            return
        }

        guard let peerManager, peerManager.hasPeers() else {
            logDiagnostics("Remote switch aborted: no peers available")
            showCommandError(title: "Uzak geçiş yapılamadı", message: "Yerel ağda başka Input Switcher bulunamadı.")
            return
        }

        logDiagnostics("Remote switch broadcast: input=\(targetInputValue) displayIdentity=\(normalizedDisplayIdentity(selectedDisplayTitle) ?? "-") peers=\(peerManager.peers.count)")

        peerManager.broadcast(
            PeerMessage(
                type: "switchRequest",
                senderID: instanceID,
                senderName: instanceName,
                displayTitle: selectedDisplayTitle,
                displayIdentity: normalizedDisplayIdentity(selectedDisplayTitle),
                isDisplayLocal: nil,
                requestedInputValue: targetInputValue
            )
        )

        let inputName = inputs.first(where: { $0.value == targetInputValue })?.menuLabel ?? "Input \(targetInputValue)"
        statusItem.button?.toolTip = "Uzak isteği gönderildi: \(inputName)"
    }

    func requestPeerStatus() {
        guard let selectedDisplayTitle = selectedDisplayTitle(),
              let peerManager,
              peerManager.hasPeers() else {
            return
        }

        logDiagnostics("Peer status request broadcast: displayIdentity=\(normalizedDisplayIdentity(selectedDisplayTitle) ?? "-") peers=\(peerManager.peers.count)")

        peerManager.broadcast(
            PeerMessage(
                type: "statusRequest",
                senderID: instanceID,
                senderName: instanceName,
                displayTitle: selectedDisplayTitle,
                displayIdentity: normalizedDisplayIdentity(selectedDisplayTitle),
                isDisplayLocal: nil,
                requestedInputValue: nil
            )
        )
    }
}

// MARK: - Settings Delegate Conformance

extension AppDelegate: SettingsDelegate {
    func didSaveSettings(inputs: [InputSource], shortcutConfig: ShortcutConfig?, displayIndex: Int, displayTitle: String) {
        logDiagnostics("Settings saved: displayTitle=\(displayTitle) displayIndex=\(displayIndex) inputs=\(inputs.map { "\($0.name)=\($0.commandMode.rawValue):\($0.value)" }.joined(separator: ","))")
        self.inputs = inputs
        self.shortcutConfig = shortcutConfig
        self.selectedDisplayIndex = displayIndex
        self.selectedDisplayTitleValue = displayTitle
        saveInputs(inputs)
        saveShortcutConfig(shortcutConfig)
        saveSelectedDisplayIndex(displayIndex)
        saveSelectedDisplayTitle(displayTitle)
        registerGlobalShortcut()
        buildMenu()
        refreshDisplayCache { [weak self] in
            self?.buildMenu()
            self?.refreshCurrentInput()
        }
    }
}

extension AppDelegate: PeerManagerDelegate {
    func peerManager(_ manager: PeerManager, didReceive message: PeerMessage) {
        let localIdentity = normalizedDisplayIdentity(selectedDisplayTitle())
        if let messageIdentity = message.displayIdentity,
           let localIdentity,
           messageIdentity != localIdentity {
            logDiagnostics("Peer message ignored: identity mismatch local=\(localIdentity) remote=\(messageIdentity) type=\(message.type)")
            return
        }

        if message.type == "statusRequest" {
            logDiagnostics("Peer status request handled from \(message.senderName)")
            refreshMonitorLocation(forceBroadcast: true)
            return
        }

        if message.type == "status", message.isDisplayLocal == true {
            if currentDisplayOption() == nil {
                knownMonitorOwnerName = message.senderName
                logDiagnostics("Peer status accepted: owner=\(message.senderName)")
                buildMenu()
            }
            return
        }

        if message.type == "switchRequest",
           currentDisplayOption() != nil,
           let requestedInputValue = message.requestedInputValue {
            knownMonitorOwnerName = message.senderName
            logDiagnostics("Peer switch request accepted: from=\(message.senderName) input=\(requestedInputValue)")
            switchToInputValue(requestedInputValue)
        } else if message.type == "switchRequest" {
            logDiagnostics("Peer switch request ignored: display not local for input=\(message.requestedInputValue.map(String.init) ?? "-")")
        }
    }
}

// MARK: - Persistence

extension AppDelegate {
    func saveInputs(_ inputs: [InputSource]) {
        let data = inputs.map {
            [
                "name": $0.name,
                "value": $0.value,
                "icon": $0.icon,
                "nickname": $0.trimmedNickname,
                "includeInShortcutCycle": $0.includeInShortcutCycle,
                "commandMode": $0.commandMode.rawValue
            ] as [String: Any]
        }
        UserDefaults.standard.set(data, forKey: "customInputs")
    }

    func loadInputs() -> [InputSource]? {
        guard let data = UserDefaults.standard.array(forKey: "customInputs") as? [[String: Any]] else {
            return nil
        }

        return data.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let value = dict["value"] as? Int,
                  let icon = dict["icon"] as? String else {
                return nil
            }

            let nickname = dict["nickname"] as? String ?? ""
            let includeInShortcutCycle = dict["includeInShortcutCycle"] as? Bool ?? false
            let commandModeRaw = dict["commandMode"] as? String
            let legacyMode = loadInputCommandMode()
            let commandMode = commandModeRaw.flatMap(InputCommandMode.init(rawValue:)) ?? legacyMode

            return InputSource(
                name: name,
                value: value,
                icon: icon,
                nickname: nickname,
                includeInShortcutCycle: includeInShortcutCycle,
                commandMode: commandMode
            )
        }
    }

    func saveLastSelectedInput(_ value: Int?) {
        if let value {
            UserDefaults.standard.set(value, forKey: "lastSelectedInputValue")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastSelectedInputValue")
        }
    }

    func loadLastSelectedInput() -> Int? {
        guard UserDefaults.standard.object(forKey: "lastSelectedInputValue") != nil else {
            return nil
        }
        return UserDefaults.standard.integer(forKey: "lastSelectedInputValue")
    }

    func saveShortcutConfig(_ config: ShortcutConfig?) {
        if let config {
            let data: [String: UInt32] = [
                "keyCode": config.keyCode,
                "carbonModifiers": config.carbonModifiers
            ]
            UserDefaults.standard.set(data, forKey: "shortcutConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "shortcutConfig")
        }
    }

    func loadShortcutConfig() -> ShortcutConfig? {
        guard let data = UserDefaults.standard.dictionary(forKey: "shortcutConfig") as? [String: UInt32],
              let keyCode = data["keyCode"],
              let carbonModifiers = data["carbonModifiers"] else {
            return nil
        }

        return ShortcutConfig(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    func saveSelectedDisplayIndex(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "selectedDisplayIndex")
    }

    func loadSelectedDisplayIndex() -> Int {
        let value = UserDefaults.standard.integer(forKey: "selectedDisplayIndex")
        return value == 0 ? 1 : value
    }

    func saveSelectedDisplayTitle(_ value: String) {
        UserDefaults.standard.set(value, forKey: "selectedDisplayTitle")
    }

    func loadSelectedDisplayTitle() -> String? {
        UserDefaults.standard.string(forKey: "selectedDisplayTitle")
    }

    func loadInputCommandMode() -> InputCommandMode {
        guard let rawValue = UserDefaults.standard.string(forKey: "inputCommandMode"),
              let mode = InputCommandMode(rawValue: rawValue) else {
            return .auto
        }
        return mode
    }

    func loadOrCreateInstanceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: "instanceID"), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: "instanceID")
        return created
    }
}

// MARK: - Shortcut Recorder

class ShortcutRecorderButton: NSButton {
    var shortcutConfig: ShortcutConfig? {
        didSet { updateAppearance() }
    }

    var statusHandler: ((String?) -> Void)?
    var isRecordingShortcut = false {
        didSet { updateAppearance() }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecordingShortcut = false
            statusHandler?("Kısayol kaydı iptal edildi.")
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            shortcutConfig = nil
            isRecordingShortcut = false
            statusHandler?("Kısayol temizlendi.")
            return
        }

        if isModifierKey(event.keyCode) {
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredModifiers = modifiers.intersection([.command, .control, .option])

        guard !requiredModifiers.isEmpty else {
            statusHandler?("En az bir Cmd, Ctrl veya Option kullan.")
            return
        }

        shortcutConfig = ShortcutConfig(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers(from: modifiers)
        )
        isRecordingShortcut = false
        statusHandler?("Kaydedilecek kısayol: \(shortcutConfig?.displayString ?? "")")
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign && isRecordingShortcut {
            isRecordingShortcut = false
            statusHandler?("Kısayol kaydı iptal edildi.")
        }
        return didResign
    }

    func beginRecording() {
        isRecordingShortcut = true
        window?.makeFirstResponder(self)
        statusHandler?("Kısayol kombinasyonuna bas. Esc iptal eder, Delete temizler.")
    }

    func clearShortcut() {
        shortcutConfig = nil
        isRecordingShortcut = false
        statusHandler?("Kısayol temizlendi.")
    }

    func updateAppearance() {
        title = isRecordingShortcut ? "Kısayola Bas..." : (shortcutConfig?.displayString ?? "Kısayol Kaydet")
    }
}

// MARK: - Diagnostics Window

class DiagnosticsWindowController: NSWindowController {
    var textView: NSTextView!
    var observer: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Tanılama Günlüğü"
        window.center()
        super.init(window: window)
        buildUI()
        observer = NotificationCenter.default.addObserver(
            forName: .diagnosticsLogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLogs()
        }
        refreshLogs()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 56, width: 720, height: 380))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = ""
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        let helpLabel = NSTextField(wrappingLabelWithString: "Copy All ile tüm günlük çıktısını kopyalayıp buraya yapıştırabilirsin.")
        helpLabel.frame = NSRect(x: 20, y: 22, width: 380, height: 28)
        helpLabel.font = NSFont.systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        contentView.addSubview(helpLabel)

        let refreshButton = NSButton(frame: NSRect(x: 490, y: 18, width: 80, height: 28))
        refreshButton.title = "Yenile"
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        contentView.addSubview(refreshButton)

        let clearButton = NSButton(frame: NSRect(x: 576, y: 18, width: 80, height: 28))
        clearButton.title = "Temizle"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAction)
        contentView.addSubview(clearButton)

        let copyButton = NSButton(frame: NSRect(x: 662, y: 18, width: 78, height: 28))
        copyButton.title = "Copy All"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyAllAction)
        contentView.addSubview(copyButton)
    }

    func refreshLogs() {
        textView.string = DiagnosticsLogStore.shared.joinedText()
        textView.scrollToEndOfDocument(nil)
    }

    @objc func refreshAction() {
        refreshLogs()
    }

    @objc func clearAction() {
        DiagnosticsLogStore.shared.clear()
    }

    @objc func copyAllAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsLogStore.shared.joinedText(), forType: .string)
    }
}

// MARK: - About Window

class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Input Switcher Hakkında"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func buildUI() {
        guard let contentView = window?.contentView else { return }

        let iconView = NSImageView(frame: NSRect(x: 24, y: 206, width: 40, height: 40))
        iconView.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        iconView.contentTintColor = .controlAccentColor
        contentView.addSubview(iconView)

        let titleLabel = makeLabel("Input Switcher", frame: NSRect(x: 76, y: 224, width: 260, height: 22), fontSize: 20, weight: .semibold, color: .labelColor)
        contentView.addSubview(titleLabel)

        let versionLabel = makeLabel("Sürüm \(appVersionString())", frame: NSRect(x: 76, y: 202, width: 260, height: 18), fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        contentView.addSubview(versionLabel)

        let descriptionLabel = makeWrappingLabel(
            "Apple Silicon Mac üzerinde m1ddc ile çalışan menü bar monitör input değiştirici.",
            frame: NSRect(x: 24, y: 146, width: 372, height: 42),
            fontSize: 13,
            color: .labelColor
        )
        contentView.addSubview(descriptionLabel)

        let noteLabel = makeWrappingLabel(
            "İki yönlü geçiş için uygulamayı iki Mac'e de kur. Bir Mac monitörden ayrıldıktan sonra o Mac geri dönüş komutu gönderemez.",
            frame: NSRect(x: 24, y: 96, width: 372, height: 38),
            fontSize: 12,
            color: .secondaryLabelColor
        )
        contentView.addSubview(noteLabel)

        let pathTitleLabel = makeLabel("Kurulum Yolu", frame: NSRect(x: 24, y: 68, width: 100, height: 18), fontSize: 11, weight: .medium, color: .secondaryLabelColor)
        contentView.addSubview(pathTitleLabel)

        let pathLabel = makeWrappingLabel(
            Bundle.main.bundlePath,
            frame: NSRect(x: 24, y: 34, width: 372, height: 34),
            fontSize: 11,
            color: .labelColor
        )
        contentView.addSubview(pathLabel)

        let closeButton = NSButton(frame: NSRect(x: 316, y: 8, width: 80, height: 28))
        closeButton.title = "Tamam"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        contentView.addSubview(closeButton)
    }

    func makeLabel(_ text: String, frame: NSRect, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.isBezeled = false
        label.isEditable = false
        label.backgroundColor = .clear
        return label
    }

    func makeWrappingLabel(_ text: String, frame: NSRect, fontSize: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.font = NSFont.systemFont(ofSize: fontSize)
        label.textColor = color
        return label
    }

    @objc func closeWindow() {
        close()
    }
}

// MARK: - Settings Window

class SettingsWindowController: NSWindowController {
    weak var delegate: SettingsDelegate?

    var inputs: [InputSource]
    var shortcutConfig: ShortcutConfig?
    var selectedDisplayIndex: Int
    var selectedDisplayTitle: String?
    var displays: [DisplayOption]
    var rows: [InputRowControls] = []
    var shortcutValueLabel: NSTextField!
    var shortcutHelpLabel: NSTextField!
    var shortcutRecordButton: ShortcutRecorderButton!
    var shortcutClearButton: NSButton!
    var displayPopup: NSPopUpButton!
    var discoverButton: NSButton!

    init(inputs: [InputSource], shortcutConfig: ShortcutConfig?, selectedDisplayIndex: Int, selectedDisplayTitle: String?, displays: [DisplayOption]) {
        self.inputs = inputs
        self.shortcutConfig = shortcutConfig
        self.selectedDisplayIndex = selectedDisplayIndex
        self.selectedDisplayTitle = selectedDisplayTitle
        self.displays = displays.isEmpty ? [DisplayOption(index: 1, title: "Display 1")] : displays

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Input Listesini Düzenle"
        window.center()

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 200, width: 940, height: 320))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let containerHeight = max(320, inputs.count * 46 + 60)
        let tableContainer = NSView(frame: NSRect(x: 0, y: 0, width: 940, height: containerHeight))

        tableContainer.addSubview(makeLabel("PORT", frame: NSRect(x: 10, y: CGFloat(containerHeight - 26), width: 150, height: 18), small: true))
        tableContainer.addSubview(makeLabel("NICKNAME", frame: NSRect(x: 170, y: CGFloat(containerHeight - 26), width: 180, height: 18), small: true))
        tableContainer.addSubview(makeLabel("DDC DEĞERİ", frame: NSRect(x: 360, y: CGFloat(containerHeight - 26), width: 100, height: 18), small: true))
        tableContainer.addSubview(makeLabel("DDC KOMUTU", frame: NSRect(x: 470, y: CGFloat(containerHeight - 26), width: 170, height: 18), small: true))
        tableContainer.addSubview(makeLabel("TEST", frame: NSRect(x: 680, y: CGFloat(containerHeight - 26), width: 60, height: 18), small: true))
        tableContainer.addSubview(makeLabel("KISAYOLDA", frame: NSRect(x: 770, y: CGFloat(containerHeight - 26), width: 90, height: 18), small: true))

        rows = []

        for (index, input) in inputs.enumerated() {
            let y = CGFloat(containerHeight - 58 - index * 46)

            let nameField = NSTextField(frame: NSRect(x: 10, y: y, width: 150, height: 28))
            nameField.stringValue = input.name
            nameField.placeholderString = "Örn. HDMI 1"
            tableContainer.addSubview(nameField)

            let nicknameField = NSTextField(frame: NSRect(x: 170, y: y, width: 180, height: 28))
            nicknameField.stringValue = input.trimmedNickname
            nicknameField.placeholderString = "Örn. İş laptopu"
            tableContainer.addSubview(nicknameField)

            let valueField = NSTextField(frame: NSRect(x: 360, y: y, width: 80, height: 28))
            valueField.stringValue = "\(input.value)"
            valueField.placeholderString = "15"
            tableContainer.addSubview(valueField)

            let commandModePopup = NSPopUpButton(frame: NSRect(x: 470, y: y, width: 190, height: 28), pullsDown: false)
            for mode in InputCommandMode.allCases {
                commandModePopup.addItem(withTitle: mode.title)
            }
            if let index = InputCommandMode.allCases.firstIndex(of: input.commandMode) {
                commandModePopup.selectItem(at: index)
            }
            commandModePopup.toolTip = "Bu input için hangi DDC komutu gönderilsin: input veya input-alt."
            tableContainer.addSubview(commandModePopup)

            let testButton = NSButton(frame: NSRect(x: 670, y: y, width: 74, height: 28))
            testButton.title = "Test"
            testButton.bezelStyle = .rounded
            testButton.target = self
            testButton.action = #selector(testInputRow(_:))
            testButton.tag = index
            testButton.toolTip = "Bu satırdaki DDC değerini ve komutu hemen dene."
            tableContainer.addSubview(testButton)

            let shortcutToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            shortcutToggle.frame = NSRect(x: 805, y: y + 4, width: 24, height: 24)
            shortcutToggle.state = input.includeInShortcutCycle ? .on : .off
            tableContainer.addSubview(shortcutToggle)

            rows.append(
                InputRowControls(
                    nameField: nameField,
                    nicknameField: nicknameField,
                    valueField: valueField,
                    commandModePopup: commandModePopup,
                    testButton: testButton,
                    shortcutToggle: shortcutToggle
                )
            )
        }

        scrollView.documentView = tableContainer
        contentView.addSubview(scrollView)

        let infoLabel = makeLabel(
            "Her input için ham DDC değeri ve DDC komutunu ayrı ayarlayabilirsin. LG monitörlerde HDMI/USB-C için genelde input-alt gerekir.",
            frame: NSRect(x: 20, y: 174, width: 940, height: 18),
            small: true
        )
        contentView.addSubview(infoLabel)

        let displayTitle = makeLabel("Monitör", frame: NSRect(x: 20, y: 146, width: 120, height: 18))
        contentView.addSubview(displayTitle)

        displayPopup = NSPopUpButton(frame: NSRect(x: 90, y: 140, width: 500, height: 28), pullsDown: false)
        for display in displays {
            displayPopup.addItem(withTitle: "[\(display.index)] \(display.title)")
        }
        if let selectedDisplayTitle,
           let selectedItemIndex = displays.firstIndex(where: { $0.title == selectedDisplayTitle }) {
            displayPopup.selectItem(at: selectedItemIndex)
        } else if let selectedItemIndex = displays.firstIndex(where: { $0.index == selectedDisplayIndex }) {
            displayPopup.selectItem(at: selectedItemIndex)
        } else {
            displayPopup.selectItem(at: 0)
            self.selectedDisplayIndex = displays[0].index
            self.selectedDisplayTitle = displays[0].title
        }
        contentView.addSubview(displayPopup)

        discoverButton = NSButton(frame: NSRect(x: 610, y: 140, width: 160, height: 28))
        discoverButton.title = "Input Keşfet..."
        discoverButton.bezelStyle = .rounded
        discoverButton.target = self
        discoverButton.action = #selector(discoverInputs)
        discoverButton.toolTip = "Seçili monitörde yaygın input/input-alt değerlerini sırayla dener ve günlüğe yazar."
        contentView.addSubview(discoverButton)

        let diagnosticsButton = NSButton(frame: NSRect(x: 780, y: 140, width: 140, height: 28))
        diagnosticsButton.title = "Günlüğü Aç"
        diagnosticsButton.bezelStyle = .rounded
        diagnosticsButton.target = self
        diagnosticsButton.action = #selector(openDiagnosticsFromSettings)
        contentView.addSubview(diagnosticsButton)

        let shortcutTitle = makeLabel("Kısayol", frame: NSRect(x: 20, y: 76, width: 120, height: 18))
        contentView.addSubview(shortcutTitle)

        shortcutValueLabel = makeLabel("", frame: NSRect(x: 20, y: 52, width: 340, height: 18))
        contentView.addSubview(shortcutValueLabel)

        shortcutHelpLabel = makeLabel("", frame: NSRect(x: 20, y: 32, width: 820, height: 18), small: true)
        contentView.addSubview(shortcutHelpLabel)

        shortcutRecordButton = ShortcutRecorderButton(frame: NSRect(x: 650, y: 46, width: 120, height: 30))
        shortcutRecordButton.bezelStyle = .rounded
        shortcutRecordButton.shortcutConfig = shortcutConfig
        shortcutRecordButton.statusHandler = { [weak self] message in
            self?.shortcutConfig = self?.shortcutRecordButton.shortcutConfig
            self?.updateShortcutUI(message: message)
        }
        contentView.addSubview(shortcutRecordButton)

        shortcutClearButton = NSButton(frame: NSRect(x: 780, y: 46, width: 100, height: 30))
        shortcutClearButton.title = "Temizle"
        shortcutClearButton.bezelStyle = .rounded
        shortcutClearButton.target = self
        shortcutClearButton.action = #selector(clearShortcut)
        contentView.addSubview(shortcutClearButton)

        let cancelButton = NSButton(frame: NSRect(x: 716, y: 8, width: 80, height: 30))
        cancelButton.title = "İptal"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(frame: NSRect(x: 804, y: 8, width: 100, height: 30))
        saveButton.title = "Kaydet"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        contentView.addSubview(saveButton)

        updateShortcutUI(message: nil)
    }

    func updateShortcutUI(message: String?) {
        if shortcutRecordButton.isRecordingShortcut {
            shortcutValueLabel.stringValue = "Kayıt bekleniyor..."
            shortcutHelpLabel.stringValue = message ?? "Kısayol kombinasyonuna bas. Esc iptal eder, Delete temizler."
            shortcutClearButton.isEnabled = false
            return
        }

        shortcutValueLabel.stringValue = "Geçerli kısayol: \(shortcutConfig?.displayString ?? "Ayarlı değil")"
        shortcutHelpLabel.stringValue = message ?? "Bu kısayol yalnızca 'Kısayolda' işaretli input'lar arasında döner."
        shortcutClearButton.isEnabled = shortcutConfig != nil
    }

    func makeLabel(_ text: String, frame: NSRect, small: Bool = false) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.font = small ? NSFont.systemFont(ofSize: 10, weight: .medium) : NSFont.systemFont(ofSize: 13)
        label.textColor = small ? .secondaryLabelColor : .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.backgroundColor = .clear
        return label
    }

    func selectedDisplayOption() -> DisplayOption? {
        let index = displayPopup.indexOfSelectedItem
        guard index >= 0, index < displays.count else { return nil }
        return displays[index]
    }

    func inputSourceForRow(_ rowIndex: Int) -> InputSource? {
        guard rowIndex >= 0, rowIndex < rows.count, rowIndex < inputs.count else { return nil }
        let row = rows[rowIndex]
        let fallback = inputs[rowIndex]
        let name = row.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = row.nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(row.valueField.stringValue) ?? fallback.value
        let commandMode = InputCommandMode.allCases[row.commandModePopup.indexOfSelectedItem]

        return InputSource(
            name: name.isEmpty ? fallback.name : name,
            value: value,
            icon: fallback.icon,
            nickname: nickname,
            includeInShortcutCycle: row.shortcutToggle.state == .on,
            commandMode: commandMode
        )
    }

    func monitorStillLocal(_ displayTitle: String) -> Bool {
        let displayIdentity = normalizedDisplayIdentity(displayTitle)
        return DDCController.availableDisplays().contains {
            normalizedDisplayIdentity($0.title) == displayIdentity
        }
    }

    func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    func presentWarningAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }

    func setTestingUIEnabled(_ isEnabled: Bool) {
        discoverButton.isEnabled = isEnabled
        for row in rows {
            row.testButton.isEnabled = isEnabled
        }
    }

    func commonDiscoveryProbes(for displayTitle: String) -> [DiscoveryProbe] {
        let isLikelyLG = displayTitle.lowercased().contains("lg")
        let lgCandidates: [DiscoveryProbe] = [
            DiscoveryProbe(label: "DisplayPort 1", source: InputSource(name: "DisplayPort 1", value: 208, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .lgAlternate)),
            DiscoveryProbe(label: "DisplayPort 2", source: InputSource(name: "DisplayPort 2", value: 209, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .lgAlternate)),
            DiscoveryProbe(label: "HDMI 1", source: InputSource(name: "HDMI 1", value: 144, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .lgAlternate)),
            DiscoveryProbe(label: "HDMI 2", source: InputSource(name: "HDMI 2", value: 145, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .lgAlternate)),
            DiscoveryProbe(label: "USB-C", source: InputSource(name: "USB-C", value: 210, icon: "cable.connector", nickname: "", includeInShortcutCycle: false, commandMode: .lgAlternate))
        ]
        let standardCandidates: [DiscoveryProbe] = [
            DiscoveryProbe(label: "DisplayPort 1", source: InputSource(name: "DisplayPort 1", value: 15, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .standard)),
            DiscoveryProbe(label: "DisplayPort 2", source: InputSource(name: "DisplayPort 2", value: 16, icon: "cable.connector.horizontal", nickname: "", includeInShortcutCycle: false, commandMode: .standard)),
            DiscoveryProbe(label: "HDMI 1", source: InputSource(name: "HDMI 1", value: 17, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .standard)),
            DiscoveryProbe(label: "HDMI 2", source: InputSource(name: "HDMI 2", value: 18, icon: "tv", nickname: "", includeInShortcutCycle: false, commandMode: .standard)),
            DiscoveryProbe(label: "USB-C", source: InputSource(name: "USB-C", value: 27, icon: "cable.connector", nickname: "", includeInShortcutCycle: false, commandMode: .standard))
        ]
        return isLikelyLG ? (lgCandidates + standardCandidates) : (standardCandidates + lgCandidates)
    }

    @objc func toggleShortcutRecording() {
        shortcutRecordButton.beginRecording()
    }

    @objc func clearShortcut() {
        shortcutRecordButton.clearShortcut()
        shortcutConfig = nil
        updateShortcutUI(message: "Kısayol temizlendi.")
    }

    @objc func openDiagnosticsFromSettings() {
        NSApp.sendAction(#selector(AppDelegate.showDiagnostics), to: nil, from: self)
    }

    @objc func testInputRow(_ sender: NSButton) {
        guard let source = inputSourceForRow(sender.tag) else { return }
        guard let display = selectedDisplayOption() else {
            presentWarningAlert(title: "Monitör seçilmedi", message: "Önce test edilecek monitörü seç.")
            return
        }

        setTestingUIEnabled(false)
        logDiagnostics("Settings row test started: display=\(display.title) input=\(source.menuLabel) mode=\(source.commandMode.rawValue) value=\(source.value)")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = DDCController.setInput(source, displayIndex: display.index, displayTitle: display.title)
            Thread.sleep(forTimeInterval: 1.0)
            let stillLocal = self.monitorStillLocal(display.title)
            let detectedValue = stillLocal ? DDCController.getCurrentInput(displayIndex: display.index) : nil
            let trimmedOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome = stillLocal ? "Monitör hâlâ bu Mac'te görünüyor." : "Monitör bu Mac'ten ayrıldı; komut input değiştirmiş olabilir."
            logDiagnostics("Settings row test finished: display=\(display.title) input=\(source.menuLabel) status=\(result.status) stillLocal=\(stillLocal) detected=\(detectedValue.map(String.init) ?? "-")")

            DispatchQueue.main.async {
                self.setTestingUIEnabled(true)
                if result.status == 0 {
                    self.presentInfoAlert(
                        title: "Test tamamlandı",
                        message: """
                        \(source.menuLabel)
                        Komut: \(source.commandMode.title) / \(source.value)

                        Sonuç: \(outcome)
                        get input: \(detectedValue.map(String.init) ?? "-")
                        Çıktı: \(trimmedOutput.isEmpty ? "Yok" : trimmedOutput)
                        """
                    )
                } else {
                    self.presentWarningAlert(
                        title: "Test başarısız",
                        message: trimmedOutput.isEmpty ? "m1ddc komutu başarısız oldu." : trimmedOutput
                    )
                }
            }
        }
    }

    @objc func discoverInputs() {
        guard let display = selectedDisplayOption() else {
            presentWarningAlert(title: "Monitör seçilmedi", message: "Önce keşif yapılacak monitörü seç.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Input keşfi başlatılsın mı?"
        alert.informativeText = """
        Yaygın input ve input-alt değerleri sırayla denenecek.
        Monitör başka bir kaynağa geçerse ve bu Mac'ten ayrılırsa keşif o noktada durur.
        Ayrıntılar Tanılama Günlüğü'ne yazılacak.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Başlat")
        alert.addButton(withTitle: "İptal")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let probes = commonDiscoveryProbes(for: display.title)
        setTestingUIEnabled(false)
        logDiagnostics("Discovery started: display=\(display.title) probes=\(probes.map { "\($0.label)=\($0.source.commandMode.rawValue):\($0.source.value)" }.joined(separator: ","))")

        DispatchQueue.global(qos: .userInitiated).async {
            var summary: [String] = []

            for probe in probes {
                let result = DDCController.setInput(probe.source, displayIndex: display.index, displayTitle: display.title)
                Thread.sleep(forTimeInterval: 1.5)
                let stillLocal = self.monitorStillLocal(display.title)
                let detectedValue = stillLocal ? DDCController.getCurrentInput(displayIndex: display.index) : nil
                let trimmedOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                summary.append("\(probe.label): \(probe.source.commandMode.title) \(probe.source.value) -> status \(result.status), local=\(stillLocal), get=\(detectedValue.map(String.init) ?? "-"), output=\(trimmedOutput.isEmpty ? "-" : trimmedOutput)")
                logDiagnostics("Discovery probe finished: display=\(display.title) label=\(probe.label) mode=\(probe.source.commandMode.rawValue) value=\(probe.source.value) status=\(result.status) stillLocal=\(stillLocal) detected=\(detectedValue.map(String.init) ?? "-")")

                if !stillLocal {
                    summary.append("Keşif durdu: monitör bu Mac'ten ayrıldı.")
                    logDiagnostics("Discovery stopped: selected display disappeared after \(probe.label)")
                    break
                }
            }

            DispatchQueue.main.async {
                self.setTestingUIEnabled(true)
                self.presentInfoAlert(
                    title: "Input keşfi tamamlandı",
                    message: """
                    Sonuçlar Tanılama Günlüğü'ne yazıldı.

                    \(summary.joined(separator: "\n"))
                    """
                )
            }
        }
    }

    @objc func save() {
        var updatedInputs: [InputSource] = []

        for (index, row) in rows.enumerated() {
            let fallback = inputs[index]
            let name = row.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let nickname = row.nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = Int(row.valueField.stringValue) ?? fallback.value
            let commandMode = InputCommandMode.allCases[row.commandModePopup.indexOfSelectedItem]

            updatedInputs.append(
                InputSource(
                    name: name.isEmpty ? fallback.name : name,
                    value: value,
                    icon: fallback.icon,
                    nickname: nickname,
                    includeInShortcutCycle: row.shortcutToggle.state == .on,
                    commandMode: commandMode
                )
            )
        }

        let selectedDisplayIndex = displays[displayPopup.indexOfSelectedItem].index
        let selectedDisplayTitle = displays[displayPopup.indexOfSelectedItem].title
        delegate?.didSaveSettings(
            inputs: updatedInputs,
            shortcutConfig: shortcutConfig,
            displayIndex: selectedDisplayIndex,
            displayTitle: selectedDisplayTitle
        )
        close()
    }

    @objc func cancel() {
        close()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
