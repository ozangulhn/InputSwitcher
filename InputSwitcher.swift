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
    var hotKey: ShortcutConfig? = nil

    var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var menuLabel: String {
        trimmedNickname.isEmpty ? name : "\(name) • \(trimmedNickname)"
    }
}

struct ShortcutConfig: Equatable {
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
    let hotKeyRecorder: ShortcutRecorderButton
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

// MARK: - Localization

enum AppLanguage: String, CaseIterable {
    case system
    case turkish = "tr"
    case english = "en"

    var title: String {
        switch self {
        case .system:
            return loc("Sistem", "System")
        case .turkish:
            return "Türkçe"
        case .english:
            return "English"
        }
    }

    static var current: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
            resolvedIsTurkish = nil
        }
    }

    private static var resolvedIsTurkish: Bool?

    static var isTurkish: Bool {
        if let resolvedIsTurkish {
            return resolvedIsTurkish
        }

        let value: Bool
        switch current {
        case .turkish:
            value = true
        case .english:
            value = false
        case .system:
            value = Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") ?? false
        }
        resolvedIsTurkish = value
        return value
    }
}

func loc(_ turkish: String, _ english: String) -> String {
    AppLanguage.isTurkish ? turkish : english
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
    var currentInputValue: Int? = nil
    var ownInputValue: Int? = nil
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
            return ShellResult(status: 1, output: loc("m1ddc bulunamadı. Homebrew yolu veya PATH kontrol edilmeli.", "m1ddc not found. Check the Homebrew path or PATH."))
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
        // Some displays (e.g. LG) always report 0, which is not a real input.
        guard let value = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
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
        if result.status != 0 || command.contains(" set input") {
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

// MARK: - Display Adjustments

enum DDCControl: String, CaseIterable {
    case luminance
    case volume
}

extension DDCController {
    static func getValue(_ control: DDCControl, displayIndex: Int) -> Int? {
        guard let m1ddcPath = resolvedM1ddcPath() else { return nil }
        let result = run("\(m1ddcPath) display \(displayIndex) get \(control.rawValue)")
        guard result.status == 0 else { return nil }
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func maxValue(_ control: DDCControl, displayIndex: Int) -> Int? {
        guard let m1ddcPath = resolvedM1ddcPath() else { return nil }
        let result = run("\(m1ddcPath) display \(displayIndex) max \(control.rawValue)")
        guard result.status == 0, let value = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    static func setValue(_ control: DDCControl, value: Int, displayIndex: Int) -> ShellResult {
        guard let m1ddcPath = resolvedM1ddcPath() else {
            return ShellResult(status: 1, output: "m1ddc missing")
        }
        return run("\(m1ddcPath) display \(displayIndex) set \(control.rawValue) \(value)")
    }

    static func setMute(_ muted: Bool, displayIndex: Int) -> ShellResult {
        guard let m1ddcPath = resolvedM1ddcPath() else {
            return ShellResult(status: 1, output: "m1ddc missing")
        }
        return run("\(m1ddcPath) display \(displayIndex) set mute \(muted ? "on" : "off")")
    }
}

class DisplayAdjustmentController {
    private let queue = DispatchQueue(label: "InputSwitcher.DisplayAdjustments")
    private var pendingWrites: [DDCControl: (value: Int, displayIndex: Int)] = [:]
    private var isWriting = false
    private var isRefreshing = false
    private var refreshCompletions: [() -> Void] = []

    private(set) var values: [DDCControl: Int] = [:]
    private(set) var maxValues: [DDCControl: Int] = [:]
    private(set) var isMuted = false
    private(set) var loadedDisplayIndex: Int?

    func maxValue(for control: DDCControl) -> Int {
        maxValues[control] ?? 100
    }

    func refresh(displayIndex: Int, completion: @escaping () -> Void) {
        refreshCompletions.append(completion)
        guard !isRefreshing else { return }
        isRefreshing = true

        queue.async {
            var readValues: [DDCControl: Int] = [:]
            var readMaxValues: [DDCControl: Int] = [:]
            for control in DDCControl.allCases {
                readValues[control] = DDCController.getValue(control, displayIndex: displayIndex)
                readMaxValues[control] = DDCController.maxValue(control, displayIndex: displayIndex)
            }

            DispatchQueue.main.async {
                self.isRefreshing = false
                self.loadedDisplayIndex = displayIndex
                for control in DDCControl.allCases {
                    if let value = readValues[control] {
                        self.values[control] = value
                    }
                    if let maxValue = readMaxValues[control] {
                        self.maxValues[control] = maxValue
                    }
                }
                logDiagnostics("Display adjustments read: display=\(displayIndex) luminance=\(readValues[.luminance].map(String.init) ?? "-")/\(readMaxValues[.luminance].map(String.init) ?? "-") volume=\(readValues[.volume].map(String.init) ?? "-")/\(readMaxValues[.volume].map(String.init) ?? "-")")
                let completions = self.refreshCompletions
                self.refreshCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    func set(_ control: DDCControl, value: Int, displayIndex: Int) {
        let clamped = min(max(value, 0), maxValue(for: control))
        values[control] = clamped

        queue.async {
            self.pendingWrites[control] = (clamped, displayIndex)
            self.drainWrites()
        }
    }

    func step(_ control: DDCControl, fraction: Double, displayIndex: Int) -> Int {
        let maxValue = maxValue(for: control)
        let current = values[control] ?? maxValue / 2
        let delta = max(1, Int((Double(maxValue) * abs(fraction)).rounded()))
        let target = fraction >= 0 ? current + delta : current - delta
        set(control, value: target, displayIndex: displayIndex)
        return values[control] ?? target
    }

    func toggleMute(displayIndex: Int) -> Bool {
        isMuted.toggle()
        let muted = isMuted
        queue.async {
            let result = DDCController.setMute(muted, displayIndex: displayIndex)
            if result.status != 0 {
                logDiagnostics("Mute command failed: muted=\(muted)")
            }
        }
        return muted
    }

    private func drainWrites() {
        guard !isWriting else { return }
        isWriting = true

        while let (control, write) = pendingWrites.first {
            pendingWrites.removeValue(forKey: control)
            let result = DDCController.setValue(control, value: write.value, displayIndex: write.displayIndex)
            if result.status != 0 {
                logDiagnostics("Adjustment failed: control=\(control.rawValue) value=\(write.value) display=\(write.displayIndex)")
            }
        }

        isWriting = false
    }
}

// MARK: - Menu Slider

class MenuSliderView: NSView {
    let iconButton: NSButton
    let slider: NSSlider
    let valueLabel: NSTextField
    var onChange: ((Int) -> Void)?
    var onIconClick: (() -> Void)?

    init(symbolName: String, accessibilityLabel: String) {
        iconButton = NSButton(frame: NSRect(x: 14, y: 5, width: 22, height: 22))
        slider = NSSlider(frame: NSRect(x: 42, y: 5, width: 168, height: 22))
        valueLabel = NSTextField(frame: NSRect(x: 214, y: 8, width: 38, height: 16))
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 32))

        iconButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        iconButton.isBordered = false
        iconButton.imagePosition = .imageOnly
        iconButton.target = self
        iconButton.action = #selector(iconClicked)
        addSubview(iconButton)

        slider.minValue = 0
        slider.maxValue = 100
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isEnabled = false
        slider.setAccessibilityLabel(accessibilityLabel)
        addSubview(slider)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.isBezeled = false
        valueLabel.isEditable = false
        valueLabel.backgroundColor = .clear
        valueLabel.stringValue = "–"
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(value: Int?, maxValue: Int) {
        slider.maxValue = Double(maxValue)
        if let value {
            slider.doubleValue = Double(value)
            slider.isEnabled = true
            valueLabel.stringValue = "\(Int((Double(value) / Double(maxValue) * 100).rounded()))%"
        } else {
            slider.isEnabled = false
            valueLabel.stringValue = "–"
        }
    }

    @objc func sliderChanged() {
        let value = Int(slider.doubleValue.rounded())
        valueLabel.stringValue = "\(Int((slider.doubleValue / max(slider.maxValue, 1) * 100).rounded()))%"
        onChange?(value)
    }

    @objc func iconClicked() {
        onIconClick?()
    }
}

// MARK: - Media Keys

enum MediaKey: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

class MediaKeyTap {
    var handler: ((MediaKey, Bool, NSEvent.ModifierFlags) -> Bool)?
    private(set) var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool {
        eventTap != nil
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = tap.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard type.rawValue == UInt32(NX_SYSDEFINED),
                  let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }

            let data1 = nsEvent.data1
            let keyCode = (data1 & 0xFFFF0000) >> 16
            let keyFlags = data1 & 0x0000FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA

            guard let key = MediaKey(rawValue: keyCode),
                  let handler = tap.handler else {
                return Unmanaged.passUnretained(event)
            }

            let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return handler(key, isKeyDown, modifiers) ? nil : Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << NX_SYSDEFINED),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}

func isBuiltInScreen(_ screen: NSScreen) -> Bool {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return false
    }
    return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
}

func screenUnderMouse() -> NSScreen? {
    let location = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
}

// MARK: - On-Screen Display

class OSDWindowController {
    private var panel: NSPanel?
    private var iconView: NSImageView!
    private var levelView: NSProgressIndicator!
    private var hideWorkItem: DispatchWorkItem?

    func show(symbolName: String, level: Double, on screen: NSScreen?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        levelView.doubleValue = min(max(level, 0), 1) * 100

        let targetScreen = screen ?? NSScreen.main
        if let frame = targetScreen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 90))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                panel?.orderOut(nil)
            })
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let effectView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        iconView = NSImageView(frame: NSRect(x: 16, y: 15, width: 24, height: 24))
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        iconView.contentTintColor = .labelColor
        effectView.addSubview(iconView)

        levelView = NSProgressIndicator(frame: NSRect(x: 52, y: 19, width: 168, height: 16))
        levelView.style = .bar
        levelView.isIndeterminate = false
        levelView.minValue = 0
        levelView.maxValue = 100
        effectView.addSubview(levelView)

        return panel
    }
}

// MARK: - Updates

let updateRepository = "ozangulhn/InputSwitcher"

struct ReleaseAsset: Decodable {
    let name: String
    let browser_download_url: String
    let size: Int?
}

struct ReleaseInfo: Decodable {
    let tag_name: String
    let html_url: String
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [ReleaseAsset]?

    var version: String { normalizedVersion(tag_name) }
}

func normalizedVersion(_ raw: String) -> String {
    var version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if version.hasPrefix("v") || version.hasPrefix("V") {
        version.removeFirst()
    }
    return version
}

func versionComponents(_ raw: String) -> [Int] {
    normalizedVersion(raw)
        .split(separator: ".", omittingEmptySubsequences: false)
        .map { Int($0.prefix(while: { ("0"..."9").contains($0) })) ?? 0 }
}

func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = versionComponents(lhs)
    let right = versionComponents(rhs)
    for index in 0..<max(left.count, right.count) {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b {
            return a < b ? .orderedAscending : .orderedDescending
        }
    }
    return .orderedSame
}

struct UpdateError: Error {
    let message: String
}

final class UpdateManager: NSObject {
    enum CheckResult {
        case available(ReleaseInfo)
        case upToDate
        case noReleases
        case failure(String)
    }

    private(set) var availableRelease: ReleaseInfo?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private var downloadPercent: Int?
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var startupTimer: Timer?
    private var periodicTimer: Timer?

    var onStateChange: (() -> Void)?
    var onProgress: (() -> Void)?

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["autoCheckForUpdates": true])
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoCheckForUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckForUpdates") }
    }

    var autoInstallEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoInstallUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "autoInstallUpdates") }
    }

    private var lastNotifiedVersion: String? {
        get { UserDefaults.standard.string(forKey: "lastNotifiedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotifiedUpdateVersion") }
    }

    func menuItemTitle() -> String {
        if isInstalling {
            if let percent = downloadPercent {
                return loc("İndiriliyor… \(percent)%", "Downloading… \(percent)%")
            }
            return loc("Yükleniyor…", "Installing…")
        }
        let version = availableRelease?.version ?? ""
        return loc("Güncelleme var: \(version) — Yükle", "Update available: \(version) — Install")
    }

    // MARK: Scheduling

    func startAutomaticChecks() {
        startupTimer?.invalidate()
        startupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.runScheduledCheck()
        }
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runScheduledCheck()
        }
    }

    private func runScheduledCheck() {
        guard autoCheckEnabled else {
            logDiagnostics("Update check skipped: automatic checks disabled")
            return
        }
        checkForUpdates(userInitiated: false)
    }

    // MARK: Checking

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking, !isInstalling else {
            logDiagnostics("Update check skipped: already \(isInstalling ? "installing" : "checking")")
            return
        }
        isChecking = true
        onStateChange?()
        logDiagnostics("Update check started: current=\(appVersionString()) repo=\(updateRepository) manual=\(userInitiated)")

        fetchLatestRelease { [weak self] result in
            DispatchQueue.main.async {
                self?.handleCheckResult(result, userInitiated: userInitiated)
            }
        }
    }

    private func fetchLatestRelease(completion: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(updateRepository)/releases/latest") else {
            completion(.failure("Invalid update URL"))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("InputSwitcher/\(appVersionString())", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure("No HTTP response"))
                return
            }
            if http.statusCode == 404 {
                completion(.noReleases)
                return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure("HTTP \(http.statusCode)"))
                return
            }
            do {
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                if release.draft == true || release.prerelease == true {
                    completion(.upToDate)
                } else if compareVersions(release.version, appVersionString()) == .orderedDescending {
                    completion(.available(release))
                } else {
                    completion(.upToDate)
                }
            } catch {
                completion(.failure("Invalid release data: \(error.localizedDescription)"))
            }
        }.resume()
    }

    private func handleCheckResult(_ result: CheckResult, userInitiated: Bool) {
        isChecking = false
        switch result {
        case .available(let release):
            availableRelease = release
            logDiagnostics("Update available: \(release.version) (current \(appVersionString()))")
            onStateChange?()
            if autoInstallEnabled && !userInitiated {
                install(release, userInitiated: false)
            } else if userInitiated || lastNotifiedVersion != release.version {
                presentAvailable(release)
            }
        case .upToDate:
            availableRelease = nil
            logDiagnostics("Update check: up to date (\(appVersionString()))")
            onStateChange?()
            if userInitiated {
                showAlert(
                    title: loc("Güncel sürümü kullanıyorsunuz", "You're up to date"),
                    message: loc("Input Switcher \(appVersionString()) en son sürüm.", "Input Switcher \(appVersionString()) is the latest version.")
                )
            }
        case .noReleases:
            availableRelease = nil
            logDiagnostics("Update check: no releases found for \(updateRepository) (404)")
            onStateChange?()
            if userInitiated {
                showAlert(
                    title: loc("Yayınlanmış sürüm yok", "No releases published"),
                    message: loc("Henüz yayınlanmış bir sürüm bulunamadı.", "No published release was found yet.")
                )
            }
        case .failure(let message):
            logDiagnostics("Update check failed: \(message)")
            onStateChange?()
            if userInitiated {
                showAlert(
                    title: loc("Güncellemeler denetlenemedi", "Couldn't check for updates"),
                    message: message
                )
            }
        }
    }

    private func releaseNotesExcerpt(_ release: ReleaseInfo) -> String {
        let text = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.count > 600 ? String(text.prefix(600)) + "…" : text
    }

    private func presentAvailable(_ release: ReleaseInfo) {
        lastNotifiedVersion = release.version
        var message = loc(
            "Yeni sürüm: \(release.version)\nMevcut sürüm: \(appVersionString())",
            "New version: \(release.version)\nCurrent version: \(appVersionString())"
        )
        let notes = releaseNotesExcerpt(release)
        if !notes.isEmpty {
            message += "\n\n" + notes
        }

        let alert = NSAlert()
        alert.messageText = loc("Güncelleme var", "Update available")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: loc("Yükle", "Install"))
        alert.addButton(withTitle: loc("Sürüm Sayfası", "Release Page"))
        alert.addButton(withTitle: loc("Sonra", "Later"))
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release, userInitiated: true)
        case .alertSecondButtonReturn:
            openReleasePage(release)
        default:
            break
        }
    }

    private func openReleasePage(_ release: ReleaseInfo) {
        if let url = URL(string: release.html_url) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc("Tamam", "OK"))
        alert.runModal()
    }

    // MARK: Installing

    func installAvailableUpdate() {
        guard let release = availableRelease else { return }
        install(release, userInitiated: true)
    }

    private func install(_ release: ReleaseInfo, userInitiated: Bool) {
        guard !isInstalling else { return }

        guard let asset = release.assets?.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
              let assetURL = URL(string: asset.browser_download_url) else {
            logDiagnostics("Update install: no .zip asset in release \(release.version)")
            if userInitiated {
                openReleasePage(release)
            }
            return
        }

        let targetURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parentPath = targetURL.deletingLastPathComponent().path
        guard targetURL.pathExtension == "app", FileManager.default.isWritableFile(atPath: parentPath) else {
            logDiagnostics("Update install: cannot replace \(targetURL.path) (not writable)")
            if userInitiated {
                showAlert(
                    title: loc("Otomatik güncelleme yapılamadı", "Can't update automatically"),
                    message: loc(
                        "Uygulamanın bulunduğu klasöre yazma izniniz yok. Sürüm sayfası açılıyor; yeni sürümü elle yükleyin.",
                        "You don't have write access to the folder containing the app. Opening the release page so you can install the new version manually."
                    )
                )
                openReleasePage(release)
            }
            return
        }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("InputSwitcherUpdate-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            finishInstallFailure(UpdateError(message: error.localizedDescription), workDir: workDir, userInitiated: userInitiated)
            return
        }

        isInstalling = true
        downloadPercent = 0
        onStateChange?()
        logDiagnostics("Update install: downloading \(asset.name) (\(release.version)) from \(assetURL.absoluteString)")

        var request = URLRequest(url: assetURL, timeoutInterval: 60)
        request.setValue("InputSwitcher/\(appVersionString())", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let expectedSize = Int64(asset.size ?? 0)
        let task = URLSession.shared.downloadTask(with: request) { [weak self] location, response, error in
            let zipURL = workDir.appendingPathComponent("update.zip")
            var failure: UpdateError?
            if let error {
                failure = UpdateError(message: error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = UpdateError(message: "HTTP \(http.statusCode)")
            } else if let location {
                do {
                    try FileManager.default.moveItem(at: location, to: zipURL)
                } catch {
                    failure = UpdateError(message: error.localizedDescription)
                }
            } else {
                failure = UpdateError(message: "Download failed")
            }

            if let failure {
                DispatchQueue.main.async {
                    self?.finishInstallFailure(failure, workDir: workDir, userInitiated: userInitiated)
                }
                return
            }

            DispatchQueue.main.async {
                self?.downloadPercent = nil
                self?.onProgress?()
            }
            DispatchQueue.global(qos: .utility).async {
                do {
                    let newApp = try UpdateManager.prepareUpdate(zipURL: zipURL, workDir: workDir, release: release)
                    let scriptURL = try UpdateManager.writeInstallScript(in: workDir)
                    DispatchQueue.main.async {
                        self?.launchInstaller(script: scriptURL, newApp: newApp, target: targetURL, workDir: workDir)
                    }
                } catch {
                    let updateError = (error as? UpdateError) ?? UpdateError(message: error.localizedDescription)
                    DispatchQueue.main.async {
                        self?.finishInstallFailure(updateError, workDir: workDir, userInitiated: userInitiated)
                    }
                }
            }
        }

        progressObservation = task.progress.observe(\.completedUnitCount) { [weak self] _, _ in
            let received = task.countOfBytesReceived
            let total = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : expectedSize
            guard total > 0 else { return }
            let percent = min(100, Int(received * 100 / total))
            DispatchQueue.main.async {
                guard let self, self.isInstalling, self.downloadPercent != nil, percent != self.downloadPercent else { return }
                self.downloadPercent = percent
                self.onProgress?()
            }
        }
        downloadTask = task
        task.resume()
    }

    private static func prepareUpdate(zipURL: URL, workDir: URL, release: ReleaseInfo) throws -> URL {
        let fileManager = FileManager.default
        let extractDir = workDir.appendingPathComponent("extracted")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        logDiagnostics("Update install: extracting \(zipURL.lastPathComponent)")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        let errorPipe = Pipe()
        ditto.standardError = errorPipe
        ditto.standardOutput = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError(message: "ditto failed (\(ditto.terminationStatus)) \(detail)")
        }

        guard let newApp = locateApp(in: extractDir) else {
            throw UpdateError(message: loc("İndirilen pakette InputSwitcher.app bulunamadı.", "InputSwitcher.app was not found in the downloaded package."))
        }

        logDiagnostics("Update install: validating \(newApp.path)")
        guard let bundle = Bundle(url: newApp), let info = bundle.infoDictionary else {
            throw UpdateError(message: loc("İndirilen uygulama okunamadı.", "The downloaded app could not be read."))
        }
        guard let currentIdentifier = Bundle.main.bundleIdentifier,
              info["CFBundleIdentifier"] as? String == currentIdentifier else {
            throw UpdateError(message: loc("İndirilen uygulamanın kimliği eşleşmiyor.", "The downloaded app's bundle identifier doesn't match."))
        }
        let downloadedVersion = info["CFBundleShortVersionString"] as? String ?? ""
        guard downloadedVersion == release.version else {
            throw UpdateError(message: loc(
                "İndirilen sürüm (\(downloadedVersion)) yayın sürümüyle (\(release.version)) eşleşmiyor.",
                "The downloaded version (\(downloadedVersion)) doesn't match the release (\(release.version))."
            ))
        }
        let executable = newApp.appendingPathComponent("Contents/MacOS/InputSwitcher").path
        guard fileManager.isExecutableFile(atPath: executable) else {
            throw UpdateError(message: loc("İndirilen uygulamada çalıştırılabilir dosya yok.", "The downloaded app has no executable."))
        }
        return newApp
    }

    private static func locateApp(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let direct = directory.appendingPathComponent("InputSwitcher.app")
        if fileManager.fileExists(atPath: direct.path) {
            return direct
        }
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "InputSwitcher.app" {
                return url
            }
            if enumerator.level >= 3 {
                enumerator.skipDescendants()
            }
        }
        return nil
    }

    private static func writeInstallScript(in workDir: URL) throws -> URL {
        let script = """
        #!/bin/bash
        # Usage: install.sh <pid> <new app> <target app> <work dir>
        PID="$1"
        NEW_APP="$2"
        TARGET="$3"
        WORK_DIR="$4"

        waited=0
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.25
            waited=$((waited + 1))
            if [ "$waited" -ge 80 ]; then
                rm -rf "$WORK_DIR"
                exit 1
            fi
        done

        BACKUP="$WORK_DIR/previous.app"
        mv "$TARGET" "$BACKUP" || rm -rf "$TARGET"
        if ! mv "$NEW_APP" "$TARGET" 2>/dev/null; then
            if ! /usr/bin/ditto "$NEW_APP" "$TARGET"; then
                rm -rf "$TARGET"
                [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET"
            fi
        fi

        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        open "$TARGET"
        rm -rf "$WORK_DIR"
        """
        let scriptURL = workDir.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func launchInstaller(script: URL, newApp: URL, target: URL, workDir: URL) {
        downloadPercent = nil
        onStateChange?()
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        logDiagnostics("Update install: launching helper, replacing \(target.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", "nohup /bin/bash \"$0\" \"$@\" >/dev/null 2>&1 &",
            script.path, pid, newApp.path, target.path, workDir.path
        ]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            finishInstallFailure(UpdateError(message: error.localizedDescription), workDir: workDir, userInitiated: true)
            return
        }
        logDiagnostics("Update install: helper started, quitting")
        NSApp.terminate(nil)
    }

    private func finishInstallFailure(_ error: UpdateError, workDir: URL, userInitiated: Bool) {
        logDiagnostics("Update install failed: \(error.message)")
        try? FileManager.default.removeItem(at: workDir)
        progressObservation = nil
        downloadTask = nil
        downloadPercent = nil
        isInstalling = false
        onStateChange?()
        if userInitiated {
            showAlert(title: loc("Güncelleme yüklenemedi", "Update failed"), message: error.message)
        }
    }
}

// MARK: - Settings Delegate

protocol SettingsDelegate: AnyObject {
    func didSaveSettings(inputs: [InputSource], shortcutConfig: ShortcutConfig?, displayIndex: Int, displayTitle: String)
    func broadcastRemoteSwitch(inputValue: Int, displayTitle: String) -> Bool
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let displayAdjustments = DisplayAdjustmentController()
    let mediaKeyTap = MediaKeyTap()
    let osd = OSDWindowController()
    var brightnessSliderView: MenuSliderView?
    var volumeSliderView: MenuSliderView?
    var menu: NSMenu!
    var currentInputValue: Int?
    var lastSelectedInputValue: Int?
    var shortcutConfig: ShortcutConfig?
    var selectedDisplayIndex = 1
    var selectedDisplayTitleValue: String?
    var hotKeyRefs: [EventHotKeyRef] = []
    var hotKeyHandlerRef: EventHandlerRef?
    var settingsWindowController: SettingsWindowController?
    var aboutWindowController: AboutWindowController?
    var diagnosticsWindowController: DiagnosticsWindowController?
    var peerManager: PeerManager?
    var monitorStatusTimer: Timer?
    let updateManager = UpdateManager()
    var updateMenuItem: NSMenuItem?
    var knownMonitorOwnerName: String?
    var instanceID: String = UUID().uuidString
    let instanceName = localMachineName()
    var lastKnownLocalPresence: Bool?
    var learnedMacNames: [Int: String] = [:]
    var pendingLearnedInput: Int?
    var lastSwitchDate = Date.distantPast
    var monitorTimerTicks = 0
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
        learnedMacNames = loadLearnedMacNames()
        logDiagnostics("App launch: name=\(instanceName) version=\(appVersionString()) displayTitle=\(selectedDisplayTitleValue ?? "-") displayIndex=\(selectedDisplayIndex)")

        setupStatusItem()
        installHotKeyHandlerIfNeeded()
        registerGlobalShortcut()
        peerManager = PeerManager(instanceID: instanceID, instanceName: instanceName)
        peerManager?.delegate = self
        peerManager?.start()
        startMonitorStatusTimer()
        mediaKeyTap.handler = { [weak self] key, isKeyDown, modifiers in
            self?.handleMediaKey(key, isKeyDown: isKeyDown, modifiers: modifiers) ?? false
        }
        updateMediaKeyTap(promptForPermission: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        updateManager.onStateChange = { [weak self] in
            self?.buildMenu()
        }
        updateManager.onProgress = { [weak self] in
            guard let self else { return }
            self.updateMenuItem?.title = self.updateManager.menuItemTitle()
        }
        buildMenu()
        updateManager.startAutomaticChecks()
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
        menu.delegate = self
        brightnessSliderView = nil
        volumeSliderView = nil

        let titleItem = NSMenuItem()
        titleItem.view = makeHeaderView()
        menu.addItem(titleItem)

        menu.addItem(.separator())

        updateMenuItem = nil
        if updateManager.availableRelease != nil || updateManager.isInstalling {
            let updateItem = NSMenuItem(title: updateManager.menuItemTitle(), action: #selector(installAvailableUpdate), keyEquivalent: "")
            updateItem.target = self
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            updateItem.isEnabled = !updateManager.isInstalling
            menu.addItem(updateItem)
            updateMenuItem = updateItem
            menu.addItem(.separator())
        }

        if !DDCController.isM1ddcAvailable() {
            let warnItem = NSMenuItem(title: loc("⚠️  m1ddc bulunamadı", "⚠️  m1ddc not found"), action: nil, keyEquivalent: "")
            warnItem.isEnabled = false
            menu.addItem(warnItem)

            let installItem = NSMenuItem(title: loc("Kurulum talimatlarını göster", "Show install instructions"), action: #selector(showInstallInstructions), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)

            menu.addItem(.separator())
        } else {
            let sectionLabel = NSMenuItem(title: loc("INPUT KAYNAĞINI SEÇ", "SELECT INPUT SOURCE"), action: nil, keyEquivalent: "")
            sectionLabel.isEnabled = false
            sectionLabel.attributedTitle = NSAttributedString(
                string: loc("INPUT KAYNAĞINI SEÇ", "SELECT INPUT SOURCE"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(sectionLabel)

            let displayName = selectedDisplayTitle() ?? loc("Monitör \(selectedDisplayIndex)", "Display \(selectedDisplayIndex)")
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

            if currentDisplayOption() != nil {
                addAdjustmentItems(to: menu)
                menu.addItem(.separator())
            }

            let cycleItem = NSMenuItem(title: cycleMenuTitle(), action: #selector(cycleShortcutInputsFromMenu), keyEquivalent: "")
            cycleItem.target = self
            cycleItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: nil)
            cycleItem.isEnabled = !shortcutCycleSources().isEmpty
            menu.addItem(cycleItem)

            let refreshItem = NSMenuItem(title: loc("Mevcut Input'u Yenile", "Refresh Current Input"), action: #selector(refreshCurrentInput), keyEquivalent: "r")
            refreshItem.target = self
            refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            menu.addItem(refreshItem)

            let ownerTitleItem = NSMenuItem(title: loc("Ekrandaki Mac'i Menü Çubuğunda Göster", "Show On-Screen Mac in Menu Bar"), action: #selector(toggleShowOwnerInMenuBar), keyEquivalent: "")
            ownerTitleItem.target = self
            ownerTitleItem.state = showOwnerInMenuBar ? .on : .off
            menu.addItem(ownerTitleItem)

            let keysItem = NSMenuItem(title: loc("Klavye Tuşları", "Keyboard Keys"), action: nil, keyEquivalent: "")
            keysItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            let keysMenu = NSMenu()
            let brightnessKeysItem = NSMenuItem(title: loc("Parlaklık tuşları harici monitörü ayarlasın", "Brightness keys control the external display"), action: #selector(toggleBrightnessKeys), keyEquivalent: "")
            brightnessKeysItem.target = self
            brightnessKeysItem.state = brightnessKeysEnabled ? .on : .off
            brightnessKeysItem.toolTip = loc("İmleç harici monitördeyken parlaklık tuşları DDC ile monitörü ayarlar. Erişilebilirlik izni gerekir.", "While the pointer is on the external display, brightness keys adjust it over DDC. Requires Accessibility permission.")
            keysMenu.addItem(brightnessKeysItem)
            let volumeKeysItem = NSMenuItem(title: loc("Ses tuşları monitör hoparlörünü ayarlasın", "Volume keys control the display speakers"), action: #selector(toggleVolumeKeys), keyEquivalent: "")
            volumeKeysItem.target = self
            volumeKeysItem.state = volumeKeysEnabled ? .on : .off
            volumeKeysItem.toolTip = loc("Monitör bu Mac'e bağlıyken ses tuşları monitör hoparlörünü DDC ile ayarlar. Erişilebilirlik izni gerekir.", "While the display is attached to this Mac, volume keys adjust its speakers over DDC. Requires Accessibility permission.")
            keysMenu.addItem(volumeKeysItem)
            if (brightnessKeysEnabled || volumeKeysEnabled) && !mediaKeyTap.isRunning {
                keysMenu.addItem(.separator())
                let permissionItem = NSMenuItem(title: loc("⚠️ Erişilebilirlik izni gerekli...", "⚠️ Accessibility permission needed..."), action: #selector(openAccessibilitySettings), keyEquivalent: "")
                permissionItem.target = self
                keysMenu.addItem(permissionItem)
            }
            keysItem.submenu = keysMenu
            menu.addItem(keysItem)

            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: loc("Input Listesini Düzenle...", "Edit Input List..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let languageItem = NSMenuItem(title: loc("Dil", "Language"), action: nil, keyEquivalent: "")
        languageItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = AppLanguage.current == language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let updatesItem = NSMenuItem(title: loc("Güncellemeler", "Updates"), action: nil, keyEquivalent: "")
        updatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        let updatesMenu = NSMenu()
        let autoCheckItem = NSMenuItem(title: loc("Güncellemeleri otomatik denetle", "Automatically check for updates"), action: #selector(toggleAutoCheckUpdates), keyEquivalent: "")
        autoCheckItem.target = self
        autoCheckItem.state = updateManager.autoCheckEnabled ? .on : .off
        updatesMenu.addItem(autoCheckItem)
        let autoInstallItem = NSMenuItem(title: loc("Güncellemeleri otomatik yükle", "Install updates automatically"), action: #selector(toggleAutoInstallUpdates), keyEquivalent: "")
        autoInstallItem.target = self
        autoInstallItem.state = updateManager.autoInstallEnabled ? .on : .off
        updatesMenu.addItem(autoInstallItem)
        updatesItem.submenu = updatesMenu
        menu.addItem(updatesItem)

        let checkUpdatesItem = NSMenuItem(title: loc("Güncellemeleri Denetle...", "Check for Updates..."), action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        checkUpdatesItem.isEnabled = !updateManager.isChecking && !updateManager.isInstalling
        menu.addItem(checkUpdatesItem)

        let aboutItem = NSMenuItem(title: loc("Hakkında", "About"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let diagnosticsItem = NSMenuItem(title: loc("Tanılama Günlüğü", "Diagnostics Log"), action: #selector(showDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        diagnosticsItem.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: loc("Çıkış", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusButtonTitle()
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
            let prefix = isResolvedFromDetectedInput(currentSource) ? loc("Aktif", "Active") : loc("Son seçilen", "Last selected")
            sublabel.stringValue = "\(prefix): \(currentSource.menuLabel)"
            sublabel.textColor = .controlAccentColor
        } else if let currentInputValue {
            sublabel.stringValue = loc("Aktif: Input \(currentInputValue)", "Active: Input \(currentInputValue)")
            sublabel.textColor = .secondaryLabelColor
        } else {
            sublabel.stringValue = loc("Aktif input bilinmiyor", "Active input unknown")
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
        let nickname = effectiveNickname(for: source)
        item.toolTip = nickname.isEmpty ? source.name : "\(source.name) - \(nickname)"
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

        let nickname = effectiveNickname(for: source)
        let isLearned = source.trimmedNickname.isEmpty && !nickname.isEmpty
        if !nickname.isEmpty {
            title.append(
                NSAttributedString(
                    string: isLearned ? "  ◦  " : "  •  ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                    ]
                )
            )
            title.append(
                NSAttributedString(
                    string: nickname,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                    ]
                )
            )
        }

        if let hotKey = source.hotKey {
            title.append(
                NSAttributedString(
                    string: "    \(hotKey.displayString)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.tertiaryLabelColor
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
            return loc("Kısayol için input seç", "Select inputs for the shortcut")
        }

        if let shortcutConfig {
            return loc("Seçili inputlar arasında geç (\(shortcutConfig.displayString))", "Cycle selected inputs (\(shortcutConfig.displayString))")
        }

        return loc("Seçili inputlar arasında geç", "Cycle selected inputs")
    }

    func shortcutCycleSources() -> [InputSource] {
        inputs.filter { $0.includeInShortcutCycle }
    }

    func switchToInputValue(_ value: Int) {
        guard DDCController.isM1ddcAvailable() else { return }
        guard let source = inputs.first(where: { $0.value == value }) else { return }
        lastSwitchDate = Date()
        pendingLearnedInput = nil
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
                        commandOutput: "",
                        displayMissing: true
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
                guard let self else { return }
                self.refreshMonitorLocation(forceBroadcast: false)
                self.requestPeerStatus()
                self.monitorTimerTicks += 1
                if self.monitorTimerTicks % 2 == 0 {
                    self.sampleCurrentInputForLearning()
                }
                if (self.brightnessKeysEnabled || self.volumeKeysEnabled) && !self.mediaKeyTap.isRunning {
                    self.updateMediaKeyTap(promptForPermission: false)
                }
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
                guard hotKeyID.signature == appDelegate.hotKeyID.signature else { return noErr }

                let pressedID = hotKeyID.id
                DispatchQueue.main.async {
                    appDelegate.handleHotKey(id: pressedID)
                }

                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &hotKeyHandlerRef
        )
    }

    static let inputHotKeyBaseID: UInt32 = 100

    func registerGlobalShortcut() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let shortcutConfig {
            registerHotKey(shortcutConfig, id: hotKeyID.id, label: "cycle")
        }

        for (index, source) in inputs.enumerated() {
            guard let hotKey = source.hotKey else { continue }
            registerHotKey(hotKey, id: AppDelegate.inputHotKeyBaseID + UInt32(index), label: source.name)
        }
    }

    func registerHotKey(_ config: ShortcutConfig, id: UInt32, label: String) {
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            EventHotKeyID(signature: hotKeyID.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        if status == noErr, let registeredHotKey {
            hotKeyRefs.append(registeredHotKey)
        } else {
            logDiagnostics("Hotkey registration failed: target=\(label) shortcut=\(config.displayString) status=\(status)")
        }
    }

    func handleHotKey(id: UInt32) {
        if id == hotKeyID.id {
            triggerShortcutCycle()
            return
        }

        guard id >= AppDelegate.inputHotKeyBaseID else { return }
        let index = Int(id - AppDelegate.inputHotKeyBaseID)
        guard index < inputs.count else { return }
        logDiagnostics("Input hotkey pressed: input=\(inputs[index].value) label=\(inputs[index].menuLabel)")
        switchToInputValue(inputs[index].value)
    }

    // MARK: - Actions

    @objc func switchInput(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        switchToInputValue(value)
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        AppLanguage.current = language
        logDiagnostics("Language changed: \(language.rawValue)")
        settingsWindowController?.close()
        settingsWindowController = nil
        aboutWindowController?.close()
        aboutWindowController = nil
        diagnosticsWindowController?.close()
        diagnosticsWindowController = nil
        buildMenu()
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
        alert.messageText = loc("m1ddc Kurulumu", "Installing m1ddc")
        let installCommands = """
        git clone https://github.com/waydabber/m1ddc
        cd m1ddc
        make
        sudo cp m1ddc /usr/local/bin/
        """
        alert.informativeText = loc(
            "m1ddc'yi kurmak için Terminal'de şunu çalıştırın:\n\n\(installCommands)\n\nKurulumdan sonra bu uygulamayı yeniden başlatın.",
            "To install m1ddc, run this in Terminal:\n\n\(installCommands)\n\nRestart this app after installing."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: loc("Tamam", "OK"))
        alert.addButton(withTitle: loc("Komutu Kopyala", "Copy Command"))

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
        settingsWindowController?.activeInputHint = currentInputValue ?? lastSelectedInputValue
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

    @objc func checkForUpdates() {
        updateManager.checkForUpdates(userInitiated: true)
    }

    @objc func installAvailableUpdate() {
        updateManager.installAvailableUpdate()
    }

    @objc func toggleAutoCheckUpdates() {
        updateManager.autoCheckEnabled.toggle()
        buildMenu()
    }

    @objc func toggleAutoInstallUpdates() {
        updateManager.autoInstallEnabled.toggle()
        buildMenu()
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
        statusItem.button?.toolTip = loc("Aktif: \(inputName)", "Active: \(inputName)")
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
        alert.addButton(withTitle: loc("Tamam", "OK"))
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

    func handleLocalSwitchFailure(targetInputValue: Int, commandOutput: String, displayMissing: Bool = false) {
        let trimmedOutput = commandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        logDiagnostics("Handle local switch failure: input=\(targetInputValue) output=\(trimmedOutput.isEmpty ? "-" : trimmedOutput)")
        if displayMissing || trimmedOutput.localizedCaseInsensitiveContains("display does not exist") {
            requestRemoteSwitch(targetInputValue: targetInputValue)
            return
        }

        showCommandError(
            title: loc("Input değiştirilemedi", "Could not switch input"),
            message: trimmedOutput.isEmpty ? loc("m1ddc komutu başarısız oldu.", "The m1ddc command failed.") : trimmedOutput
        )
    }

    func refreshMonitorLocation(forceBroadcast: Bool) {
        let isLocal = currentDisplayOption() != nil
        let previousOwnerName = knownMonitorOwnerName

        if isLocal {
            knownMonitorOwnerName = instanceName
        } else if knownMonitorOwnerName == instanceName {
            knownMonitorOwnerName = lastSelectedInputValue
                .flatMap { learnedMacNames[$0] }
                .flatMap { $0 == instanceName ? nil : $0 }
        }

        if forceBroadcast || lastKnownLocalPresence != isLocal || previousOwnerName != knownMonitorOwnerName {
            logDiagnostics("Refresh monitor location: isLocal=\(isLocal) selectedDisplay=\(selectedDisplayTitle() ?? "-") owner=\(knownMonitorOwnerName ?? "-") force=\(forceBroadcast)")
        }

        if forceBroadcast || lastKnownLocalPresence != isLocal {
            lastKnownLocalPresence = isLocal
            buildMenu()

            if let selectedDisplayTitle = selectedDisplayTitle() {
                var message = PeerMessage(
                    type: "status",
                    senderID: instanceID,
                    senderName: instanceName,
                    displayTitle: selectedDisplayTitle,
                    displayIdentity: normalizedDisplayIdentity(selectedDisplayTitle),
                    isDisplayLocal: isLocal,
                    requestedInputValue: nil
                )
                message.currentInputValue = isLocal ? currentInputValue : nil
                message.ownInputValue = learnedMacNames.first(where: { $0.value == instanceName })?.key
                peerManager?.broadcast(message)
            }
        } else if previousOwnerName != knownMonitorOwnerName {
            buildMenu()
        }
    }

    func sampleCurrentInputForLearning() {
        guard let displayIndex = currentDisplayIndex(),
              Date().timeIntervalSince(lastSwitchDate) > 8 else {
            pendingLearnedInput = nil
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let value = DDCController.getCurrentInput(displayIndex: displayIndex)
            DispatchQueue.main.async {
                self.handleSampledInput(value)
            }
        }
    }

    func handleSampledInput(_ value: Int?) {
        guard let value,
              currentDisplayOption() != nil,
              Date().timeIntervalSince(lastSwitchDate) > 8 else {
            pendingLearnedInput = nil
            return
        }

        let changed = currentInputValue != value
        currentInputValue = value

        if pendingLearnedInput == value {
            learnMacName(instanceName, forInput: value)
        }
        pendingLearnedInput = value

        if changed {
            refreshMonitorLocation(forceBroadcast: true)
        }
    }

    func learnMacName(_ name: String, forInput value: Int) {
        guard learnedMacNames[value] != name else { return }
        learnedMacNames = learnedMacNames.filter { $0.value != name }
        learnedMacNames[value] = name
        saveLearnedMacNames(learnedMacNames)
        logDiagnostics("Learned input owner: input=\(value) mac=\(name)")

        if name == instanceName {
            refreshMonitorLocation(forceBroadcast: true)
        } else {
            buildMenu()
        }
    }

    func learnedNickname(for source: InputSource) -> String? {
        guard let name = learnedMacNames[source.value] else { return nil }
        return name == instanceName ? loc("Bu Mac", "This Mac") : name
    }

    func effectiveNickname(for source: InputSource) -> String {
        source.trimmedNickname.isEmpty ? (learnedNickname(for: source) ?? "") : source.trimmedNickname
    }

    var showOwnerInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "showOwnerInMenuBar") }
        set { UserDefaults.standard.set(newValue, forKey: "showOwnerInMenuBar") }
    }

    func onScreenLabel() -> String? {
        let ownerName = currentDisplayOption() != nil ? instanceName : knownMonitorOwnerName
        if let currentInputValue,
           let source = inputs.first(where: { $0.value == currentInputValue }),
           !source.trimmedNickname.isEmpty {
            return source.trimmedNickname
        }
        return ownerName
    }

    func updateStatusButtonTitle() {
        guard let button = statusItem?.button else { return }

        guard showOwnerInMenuBar, let label = onScreenLabel() else {
            button.title = ""
            button.imagePosition = .imageOnly
            return
        }

        let maxLength = 18
        let shortLabel = label.count > maxLength ? String(label.prefix(maxLength - 1)) + "…" : label
        button.title = " \(shortLabel)"
        button.imagePosition = .imageLeading
    }

    // MARK: Display adjustments

    func addAdjustmentItems(to menu: NSMenu) {
        let brightnessView = MenuSliderView(symbolName: "sun.max", accessibilityLabel: loc("Parlaklık", "Brightness"))
        brightnessView.toolTip = loc("Monitör parlaklığı (DDC)", "Display brightness (DDC)")
        brightnessView.onChange = { [weak self] value in
            guard let self, let displayIndex = self.currentDisplayIndex() else { return }
            self.displayAdjustments.set(.luminance, value: value, displayIndex: displayIndex)
        }
        let brightnessItem = NSMenuItem()
        brightnessItem.view = brightnessView
        menu.addItem(brightnessItem)
        brightnessSliderView = brightnessView

        let volumeView = MenuSliderView(symbolName: displayAdjustments.isMuted ? "speaker.slash" : "speaker.wave.2", accessibilityLabel: loc("Ses", "Volume"))
        volumeView.toolTip = loc("Monitör hoparlör sesi (DDC). Simgeye tıkla: sessiz.", "Display speaker volume (DDC). Click the icon to mute.")
        volumeView.onChange = { [weak self] value in
            guard let self, let displayIndex = self.currentDisplayIndex() else { return }
            self.displayAdjustments.set(.volume, value: value, displayIndex: displayIndex)
        }
        volumeView.onIconClick = { [weak self] in
            self?.toggleDisplayMute()
        }
        let volumeItem = NSMenuItem()
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        volumeSliderView = volumeView

        updateAdjustmentSliders()
    }

    func updateAdjustmentSliders() {
        brightnessSliderView?.update(value: displayAdjustments.values[.luminance], maxValue: displayAdjustments.maxValue(for: .luminance))
        volumeSliderView?.update(value: displayAdjustments.values[.volume], maxValue: displayAdjustments.maxValue(for: .volume))
        volumeSliderView?.iconButton.image = NSImage(
            systemSymbolName: displayAdjustments.isMuted ? "speaker.slash" : "speaker.wave.2",
            accessibilityDescription: loc("Ses", "Volume")
        )
    }

    func refreshAdjustments(completion: (() -> Void)? = nil) {
        guard let displayIndex = currentDisplayIndex() else { return }
        displayAdjustments.refresh(displayIndex: displayIndex) { [weak self] in
            self?.updateAdjustmentSliders()
            completion?()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        refreshAdjustments()
    }

    func toggleDisplayMute() {
        guard let displayIndex = currentDisplayIndex() else { return }
        let muted = displayAdjustments.toggleMute(displayIndex: displayIndex)
        updateAdjustmentSliders()
        let volume = Double(displayAdjustments.values[.volume] ?? 0) / Double(displayAdjustments.maxValue(for: .volume))
        osd.show(symbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", level: muted ? 0 : volume, on: screenUnderMouse())
    }

    // MARK: Media keys

    var brightnessKeysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "brightnessKeysControlDisplay") }
        set { UserDefaults.standard.set(newValue, forKey: "brightnessKeysControlDisplay") }
    }

    var volumeKeysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "volumeKeysControlDisplay") }
        set { UserDefaults.standard.set(newValue, forKey: "volumeKeysControlDisplay") }
    }

    @objc func toggleBrightnessKeys() {
        brightnessKeysEnabled.toggle()
        updateMediaKeyTap(promptForPermission: brightnessKeysEnabled)
        buildMenu()
    }

    @objc func toggleVolumeKeys() {
        volumeKeysEnabled.toggle()
        updateMediaKeyTap(promptForPermission: volumeKeysEnabled)
        buildMenu()
    }

    @objc func openAccessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func updateMediaKeyTap(promptForPermission: Bool) {
        guard brightnessKeysEnabled || volumeKeysEnabled else {
            if mediaKeyTap.isRunning {
                mediaKeyTap.stop()
                logDiagnostics("Media key tap stopped")
            }
            return
        }

        guard !mediaKeyTap.isRunning else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            if promptForPermission {
                logDiagnostics("Media key tap waiting for Accessibility permission")
            }
            return
        }

        if mediaKeyTap.start() {
            logDiagnostics("Media key tap started")
            buildMenu()
        } else {
            logDiagnostics("Media key tap failed to start")
        }
    }

    func handleMediaKey(_ key: MediaKey, isKeyDown: Bool, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let displayIndex = currentDisplayIndex() else { return false }

        let control: DDCControl
        let isIncrease: Bool
        switch key {
        case .brightnessUp, .brightnessDown:
            guard brightnessKeysEnabled else { return false }
            if let screen = screenUnderMouse(), isBuiltInScreen(screen) {
                return false
            }
            control = .luminance
            isIncrease = key == .brightnessUp
        case .soundUp, .soundDown:
            guard volumeKeysEnabled else { return false }
            control = .volume
            isIncrease = key == .soundUp
        case .mute:
            guard volumeKeysEnabled else { return false }
            if isKeyDown {
                toggleDisplayMute()
            }
            return true
        }

        guard isKeyDown else { return true }

        let isFineStep = modifiers.contains(.option) && modifiers.contains(.shift)
        let fraction = (isFineStep ? 1.0 / 64.0 : 1.0 / 16.0) * (isIncrease ? 1 : -1)

        let applyStep = { [weak self] in
            guard let self else { return }
            let value = self.displayAdjustments.step(control, fraction: fraction, displayIndex: displayIndex)
            let level = Double(value) / Double(self.displayAdjustments.maxValue(for: control))
            let symbol = control == .luminance ? "sun.max.fill" : (level == 0 ? "speaker.fill" : "speaker.wave.2.fill")
            self.updateAdjustmentSliders()
            self.osd.show(symbolName: symbol, level: level, on: screenUnderMouse())
        }

        if displayAdjustments.values[control] == nil || displayAdjustments.loadedDisplayIndex != displayIndex {
            refreshAdjustments(completion: applyStep)
        } else {
            applyStep()
        }
        return true
    }

    @objc func toggleShowOwnerInMenuBar() {
        showOwnerInMenuBar.toggle()
        buildMenu()
    }

    func monitorLocationText() -> String {
        if currentDisplayOption() != nil {
            return loc("Ekranda: Bu Mac (\(instanceName))", "On screen: This Mac (\(instanceName))")
        }

        if let knownMonitorOwnerName {
            return loc("Ekranda: \(knownMonitorOwnerName)", "On screen: \(knownMonitorOwnerName)")
        }

        return loc("Monitör: Ağda aranıyor", "Display: Searching network")
    }

    func requestRemoteSwitch(targetInputValue: Int) {
        guard let selectedDisplayTitle = selectedDisplayTitle() else {
            logDiagnostics("Remote switch aborted: no selected display title")
            showCommandError(title: loc("Uzak geçiş yapılamadı", "Remote switch failed"), message: loc("Önce hedef monitörü seç.", "Select the target display first."))
            return
        }

        guard let peerManager, peerManager.hasPeers() else {
            logDiagnostics("Remote switch aborted: no peers available")
            showCommandError(title: loc("Uzak geçiş yapılamadı", "Remote switch failed"), message: loc("Yerel ağda başka Input Switcher bulunamadı.", "No other Input Switcher found on the local network."))
            return
        }

        _ = broadcastRemoteSwitch(inputValue: targetInputValue, displayTitle: selectedDisplayTitle)

        let inputName = inputs.first(where: { $0.value == targetInputValue })?.menuLabel ?? "Input \(targetInputValue)"
        statusItem.button?.toolTip = loc("Uzak isteği gönderildi: \(inputName)", "Remote request sent: \(inputName)")
    }

    func broadcastRemoteSwitch(inputValue: Int, displayTitle: String) -> Bool {
        guard let peerManager, peerManager.hasPeers() else { return false }

        logDiagnostics("Remote switch broadcast: input=\(inputValue) displayIdentity=\(normalizedDisplayIdentity(displayTitle) ?? "-") peers=\(peerManager.peers.count)")

        peerManager.broadcast(
            PeerMessage(
                type: "switchRequest",
                senderID: instanceID,
                senderName: instanceName,
                displayTitle: displayTitle,
                displayIdentity: normalizedDisplayIdentity(displayTitle),
                isDisplayLocal: nil,
                requestedInputValue: inputValue
            )
        )
        return true
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

        if message.type == "status" {
            if let ownInputValue = message.ownInputValue {
                learnMacName(message.senderName, forInput: ownInputValue)
            }

            guard currentDisplayOption() == nil else { return }

            if message.isDisplayLocal == true {
                knownMonitorOwnerName = message.senderName
                if let remoteInputValue = message.currentInputValue {
                    currentInputValue = remoteInputValue
                }
                logDiagnostics("Peer status accepted: owner=\(message.senderName) input=\(message.currentInputValue.map(String.init) ?? "-")")
                buildMenu()
            } else if knownMonitorOwnerName == message.senderName {
                knownMonitorOwnerName = nil
                logDiagnostics("Peer status: \(message.senderName) no longer owns the display")
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
                "commandMode": $0.commandMode.rawValue,
                "hotKeyCode": $0.hotKey.map { Int($0.keyCode) } ?? -1,
                "hotKeyModifiers": $0.hotKey.map { Int($0.carbonModifiers) } ?? 0
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
            let hotKeyCode = dict["hotKeyCode"] as? Int ?? -1
            let hotKeyModifiers = dict["hotKeyModifiers"] as? Int ?? 0
            let hotKey = hotKeyCode >= 0 ? ShortcutConfig(keyCode: UInt32(hotKeyCode), carbonModifiers: UInt32(hotKeyModifiers)) : nil

            return InputSource(
                name: name,
                value: value,
                icon: icon,
                nickname: nickname,
                includeInShortcutCycle: includeInShortcutCycle,
                commandMode: commandMode,
                hotKey: hotKey
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

    func saveLearnedMacNames(_ names: [Int: String]) {
        let data = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(data, forKey: "learnedMacNames")
    }

    func loadLearnedMacNames() -> [Int: String] {
        guard let data = UserDefaults.standard.dictionary(forKey: "learnedMacNames") as? [String: String] else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: data.compactMap { key, value in Int(key).flatMap { $0 > 0 ? ($0, value) : nil } })
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
    var emptyTitle: String? {
        didSet { updateAppearance() }
    }
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
            statusHandler?(loc("Kısayol kaydı iptal edildi.", "Shortcut recording cancelled."))
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            shortcutConfig = nil
            isRecordingShortcut = false
            statusHandler?(loc("Kısayol temizlendi.", "Shortcut cleared."))
            return
        }

        if isModifierKey(event.keyCode) {
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredModifiers = modifiers.intersection([.command, .control, .option])

        guard !requiredModifiers.isEmpty else {
            statusHandler?(loc("En az bir Cmd, Ctrl veya Option kullan.", "Use at least one of Cmd, Ctrl or Option."))
            return
        }

        shortcutConfig = ShortcutConfig(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers(from: modifiers)
        )
        isRecordingShortcut = false
        statusHandler?(loc("Kaydedilecek kısayol: \(shortcutConfig?.displayString ?? "")", "Shortcut to save: \(shortcutConfig?.displayString ?? "")"))
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign && isRecordingShortcut {
            isRecordingShortcut = false
            statusHandler?(loc("Kısayol kaydı iptal edildi.", "Shortcut recording cancelled."))
        }
        return didResign
    }

    func beginRecording() {
        isRecordingShortcut = true
        window?.makeFirstResponder(self)
        statusHandler?(loc("Kısayol kombinasyonuna bas. Esc iptal eder, Delete temizler.", "Press a key combination. Esc cancels, Delete clears."))
    }

    func clearShortcut() {
        shortcutConfig = nil
        isRecordingShortcut = false
        statusHandler?(loc("Kısayol temizlendi.", "Shortcut cleared."))
    }

    func updateAppearance() {
        title = isRecordingShortcut ? loc("Kısayola Bas...", "Press Shortcut...") : (shortcutConfig?.displayString ?? emptyTitle ?? loc("Kısayol Kaydet", "Record Shortcut"))
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

        window.title = loc("Tanılama Günlüğü", "Diagnostics Log")
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

        let helpLabel = NSTextField(wrappingLabelWithString: loc("Copy All ile tüm günlük çıktısını kopyalayıp paylaşabilirsin.", "Use Copy All to copy the whole log and share it."))
        helpLabel.frame = NSRect(x: 20, y: 22, width: 380, height: 28)
        helpLabel.font = NSFont.systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        contentView.addSubview(helpLabel)

        let refreshButton = NSButton(frame: NSRect(x: 490, y: 18, width: 80, height: 28))
        refreshButton.title = loc("Yenile", "Refresh")
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        contentView.addSubview(refreshButton)

        let clearButton = NSButton(frame: NSRect(x: 576, y: 18, width: 80, height: 28))
        clearButton.title = loc("Temizle", "Clear")
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

        window.title = loc("Input Switcher Hakkında", "About Input Switcher")
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

        let versionLabel = makeLabel(loc("Sürüm \(appVersionString())", "Version \(appVersionString())"), frame: NSRect(x: 76, y: 202, width: 260, height: 18), fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        contentView.addSubview(versionLabel)

        let descriptionLabel = makeWrappingLabel(
            loc("Apple Silicon Mac üzerinde m1ddc ile çalışan menü bar monitör input değiştirici.", "A menu bar display input switcher for Apple Silicon Macs, powered by m1ddc."),
            frame: NSRect(x: 24, y: 146, width: 372, height: 42),
            fontSize: 13,
            color: .labelColor
        )
        contentView.addSubview(descriptionLabel)

        let noteLabel = makeWrappingLabel(
            loc("İki yönlü geçiş için uygulamayı iki Mac'e de kur. Bir Mac monitörden ayrıldıktan sonra o Mac geri dönüş komutu gönderemez.", "Install the app on both Macs to switch both ways. Once a Mac leaves the display, it can only switch back through the other Mac."),
            frame: NSRect(x: 24, y: 96, width: 372, height: 38),
            fontSize: 12,
            color: .secondaryLabelColor
        )
        contentView.addSubview(noteLabel)

        let pathTitleLabel = makeLabel(loc("Kurulum Yolu", "Install Path"), frame: NSRect(x: 24, y: 68, width: 100, height: 18), fontSize: 11, weight: .medium, color: .secondaryLabelColor)
        contentView.addSubview(pathTitleLabel)

        let pathLabel = makeWrappingLabel(
            Bundle.main.bundlePath,
            frame: NSRect(x: 24, y: 34, width: 372, height: 34),
            fontSize: 11,
            color: .labelColor
        )
        contentView.addSubview(pathLabel)

        let closeButton = NSButton(frame: NSRect(x: 316, y: 8, width: 80, height: 28))
        closeButton.title = loc("Tamam", "OK")
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
    var activeInputHint: Int?

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

        window.title = loc("Input Listesini Düzenle", "Edit Input List")
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
        tableContainer.addSubview(makeLabel(loc("TAKMA AD", "NICKNAME"), frame: NSRect(x: 170, y: CGFloat(containerHeight - 26), width: 180, height: 18), small: true))
        tableContainer.addSubview(makeLabel(loc("DDC DEĞERİ", "DDC VALUE"), frame: NSRect(x: 360, y: CGFloat(containerHeight - 26), width: 100, height: 18), small: true))
        tableContainer.addSubview(makeLabel(loc("DDC KOMUTU", "DDC COMMAND"), frame: NSRect(x: 470, y: CGFloat(containerHeight - 26), width: 170, height: 18), small: true))
        tableContainer.addSubview(makeLabel("TEST", frame: NSRect(x: 680, y: CGFloat(containerHeight - 26), width: 60, height: 18), small: true))
        tableContainer.addSubview(makeLabel(loc("DÖNGÜDE", "IN CYCLE"), frame: NSRect(x: 752, y: CGFloat(containerHeight - 26), width: 80, height: 18), small: true))
        tableContainer.addSubview(makeLabel(loc("KISAYOL", "HOTKEY"), frame: NSRect(x: 832, y: CGFloat(containerHeight - 26), width: 100, height: 18), small: true))

        rows = []

        for (index, input) in inputs.enumerated() {
            let y = CGFloat(containerHeight - 58 - index * 46)

            let nameField = NSTextField(frame: NSRect(x: 10, y: y, width: 150, height: 28))
            nameField.stringValue = input.name
            nameField.placeholderString = loc("Örn. HDMI 1", "e.g. HDMI 1")
            tableContainer.addSubview(nameField)

            let nicknameField = NSTextField(frame: NSRect(x: 170, y: y, width: 180, height: 28))
            nicknameField.stringValue = input.trimmedNickname
            nicknameField.placeholderString = loc("Örn. İş laptopu", "e.g. Work laptop")
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
            commandModePopup.toolTip = loc("Bu input için hangi DDC komutu gönderilsin: input veya input-alt.", "Which DDC command to send for this input: input or input-alt.")
            tableContainer.addSubview(commandModePopup)

            let testButton = NSButton(frame: NSRect(x: 670, y: y, width: 74, height: 28))
            testButton.title = "Test"
            testButton.bezelStyle = .rounded
            testButton.target = self
            testButton.action = #selector(testInputRow(_:))
            testButton.tag = index
            testButton.toolTip = loc("Bu satırdaki DDC değerini ve komutu hemen dene.", "Try this row's DDC value and command now.")
            tableContainer.addSubview(testButton)

            let shortcutToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            shortcutToggle.frame = NSRect(x: 775, y: y + 4, width: 24, height: 24)
            shortcutToggle.state = input.includeInShortcutCycle ? .on : .off
            tableContainer.addSubview(shortcutToggle)

            let hotKeyRecorder = ShortcutRecorderButton(frame: NSRect(x: 822, y: y, width: 108, height: 28))
            hotKeyRecorder.bezelStyle = .rounded
            hotKeyRecorder.font = NSFont.systemFont(ofSize: 11)
            hotKeyRecorder.emptyTitle = loc("Ata", "Set")
            hotKeyRecorder.shortcutConfig = input.hotKey
            hotKeyRecorder.toolTip = loc("Bu input'a doğrudan geçen global kısayol. Kayıt sırasında Delete temizler.", "Global shortcut that switches straight to this input. Press Delete while recording to clear.")
            hotKeyRecorder.statusHandler = { [weak self] message in
                self?.shortcutHelpLabel.stringValue = message ?? ""
            }
            tableContainer.addSubview(hotKeyRecorder)

            rows.append(
                InputRowControls(
                    nameField: nameField,
                    nicknameField: nicknameField,
                    valueField: valueField,
                    commandModePopup: commandModePopup,
                    testButton: testButton,
                    shortcutToggle: shortcutToggle,
                    hotKeyRecorder: hotKeyRecorder
                )
            )
        }

        scrollView.documentView = tableContainer
        contentView.addSubview(scrollView)

        let infoLabel = makeLabel(
            loc("Her input için ham DDC değeri ve DDC komutunu ayrı ayarlayabilirsin. LG monitörlerde HDMI/USB-C için genelde input-alt gerekir.", "Set the raw DDC value and DDC command per input. LG displays usually need input-alt for HDMI/USB-C."),
            frame: NSRect(x: 20, y: 174, width: 940, height: 18),
            small: true
        )
        contentView.addSubview(infoLabel)

        let displayTitle = makeLabel(loc("Monitör", "Display"), frame: NSRect(x: 20, y: 146, width: 120, height: 18))
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
        discoverButton.title = loc("Input Keşfet...", "Discover Inputs...")
        discoverButton.bezelStyle = .rounded
        discoverButton.target = self
        discoverButton.action = #selector(discoverInputs)
        discoverButton.toolTip = loc("Yaygın input/input-alt değerlerini sırayla dener, her denemeden sonra ne gördüğünü sorar ve bulunan değerleri listeye uygular.", "Tries common input/input-alt values one by one, asks what you saw after each try, and can apply the findings to the list.")
        contentView.addSubview(discoverButton)

        let diagnosticsButton = NSButton(frame: NSRect(x: 780, y: 140, width: 140, height: 28))
        diagnosticsButton.title = loc("Günlüğü Aç", "Open Log")
        diagnosticsButton.bezelStyle = .rounded
        diagnosticsButton.target = self
        diagnosticsButton.action = #selector(openDiagnosticsFromSettings)
        contentView.addSubview(diagnosticsButton)

        let shortcutTitle = makeLabel(loc("Döngü Kısayolu", "Cycle Shortcut"), frame: NSRect(x: 20, y: 76, width: 120, height: 18))
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
        shortcutClearButton.title = loc("Temizle", "Clear")
        shortcutClearButton.bezelStyle = .rounded
        shortcutClearButton.target = self
        shortcutClearButton.action = #selector(clearShortcut)
        contentView.addSubview(shortcutClearButton)

        let cancelButton = NSButton(frame: NSRect(x: 716, y: 8, width: 80, height: 30))
        cancelButton.title = loc("İptal", "Cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(frame: NSRect(x: 804, y: 8, width: 100, height: 30))
        saveButton.title = loc("Kaydet", "Save")
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        contentView.addSubview(saveButton)

        updateShortcutUI(message: nil)
    }

    func updateShortcutUI(message: String?) {
        if shortcutRecordButton.isRecordingShortcut {
            shortcutValueLabel.stringValue = loc("Kayıt bekleniyor...", "Waiting for shortcut...")
            shortcutHelpLabel.stringValue = message ?? loc("Kısayol kombinasyonuna bas. Esc iptal eder, Delete temizler.", "Press a key combination. Esc cancels, Delete clears.")
            shortcutClearButton.isEnabled = false
            return
        }

        shortcutValueLabel.stringValue = loc("Geçerli kısayol: \(shortcutConfig?.displayString ?? "Ayarlı değil")", "Current shortcut: \(shortcutConfig?.displayString ?? "Not set")")
        shortcutHelpLabel.stringValue = message ?? loc("Bu kısayol yalnızca 'Döngüde' işaretli input'lar arasında döner.", "This shortcut cycles only through inputs marked 'In Cycle'.")
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
            commandMode: commandMode,
            hotKey: row.hotKeyRecorder.shortcutConfig
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
        alert.addButton(withTitle: loc("Tamam", "OK"))
        alert.runModal()
    }

    func presentWarningAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc("Tamam", "OK"))
        alert.runModal()
    }

    func setTestingUIEnabled(_ isEnabled: Bool) {
        discoverButton.isEnabled = isEnabled
        for row in rows {
            row.testButton.isEnabled = isEnabled
        }
    }

    @objc func toggleShortcutRecording() {
        shortcutRecordButton.beginRecording()
    }

    @objc func clearShortcut() {
        shortcutRecordButton.clearShortcut()
        shortcutConfig = nil
        updateShortcutUI(message: loc("Kısayol temizlendi.", "Shortcut cleared."))
    }

    @objc func openDiagnosticsFromSettings() {
        NSApp.sendAction(#selector(AppDelegate.showDiagnostics), to: nil, from: self)
    }

    @objc func testInputRow(_ sender: NSButton) {
        guard let source = inputSourceForRow(sender.tag) else { return }
        guard let display = selectedDisplayOption() else {
            presentWarningAlert(title: loc("Monitör seçilmedi", "No display selected"), message: loc("Önce test edilecek monitörü seç.", "Select the display to test first."))
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
            let outcome = stillLocal ? loc("Monitör hâlâ bu Mac'te görünüyor.", "The display is still attached to this Mac.") : loc("Monitör bu Mac'ten ayrıldı; komut input değiştirmiş olabilir.", "The display left this Mac; the command probably switched the input.")
            logDiagnostics("Settings row test finished: display=\(display.title) input=\(source.menuLabel) status=\(result.status) stillLocal=\(stillLocal) detected=\(detectedValue.map(String.init) ?? "-")")

            DispatchQueue.main.async {
                self.setTestingUIEnabled(true)
                if result.status == 0 {
                    self.presentInfoAlert(
                        title: loc("Test tamamlandı", "Test finished"),
                        message: """
                        \(source.menuLabel)
                        \(loc("Komut", "Command")): \(source.commandMode.title) / \(source.value)

                        \(loc("Sonuç", "Result")): \(outcome)
                        get input: \(detectedValue.map(String.init) ?? "-")
                        \(loc("Çıktı", "Output")): \(trimmedOutput.isEmpty ? "-" : trimmedOutput)
                        """
                    )
                } else {
                    self.presentWarningAlert(
                        title: loc("Test başarısız", "Test failed"),
                        message: trimmedOutput.isEmpty ? loc("m1ddc komutu başarısız oldu.", "The m1ddc command failed.") : trimmedOutput
                    )
                }
            }
        }
    }

    // MARK: - Guided Discovery

    struct DiscoveryCandidate: Equatable {
        let mode: InputCommandMode
        let value: Int

        var command: String { "\(mode.commandName) \(value)" }
    }

    enum DiscoveryAnswer {
        case noChange
        case unsure
        case port(String)
    }

    final class DiscoverySession {
        let display: DisplayOption
        let home: InputSource
        let candidates: [DiscoveryCandidate]
        var index = 0
        var answers: [(candidate: DiscoveryCandidate, answer: DiscoveryAnswer)] = []
        var stoppedEarly = false

        init(display: DisplayOption, home: InputSource, candidates: [DiscoveryCandidate]) {
            self.display = display
            self.home = home
            self.candidates = candidates
        }
    }

    static let discoveryStandardPortNames = ["DisplayPort 1", "DisplayPort 2", "HDMI 1", "HDMI 2", "USB-C"]

    func discoveryCandidates(for displayTitle: String, home: InputSource) -> [DiscoveryCandidate] {
        let alternate = [208, 209, 210, 144, 145].map { DiscoveryCandidate(mode: .lgAlternate, value: $0) }
        let standard = [15, 16, 17, 18, 27].map { DiscoveryCandidate(mode: .standard, value: $0) }
        let isLikelyLG = displayTitle.lowercased().contains("lg")
        let homeMode = DDCController.resolvedCommandMode(home.commandMode, displayTitle: displayTitle)
        let homeValue = DDCController.resolvedDDCValue(for: home.value, mode: home.commandMode, displayTitle: displayTitle)
        return (isLikelyLG ? alternate + standard : standard + alternate)
            .filter { !($0.mode == homeMode && $0.value == homeValue) }
    }

    func makeMenuPopup(titles: [String], width: CGFloat) -> NSPopUpButton {
        // addItem(withTitle:) merges duplicate titles, so build the items by hand.
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 26), pullsDown: false)
        for title in titles {
            popup.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        return popup
    }

    @objc func discoverInputs() {
        guard let display = selectedDisplayOption() else {
            presentWarningAlert(title: loc("Monitör seçilmedi", "No display selected"), message: loc("Önce keşif yapılacak monitörü seç.", "Select the display to scan first."))
            return
        }

        let rowSources = rows.indices.compactMap { inputSourceForRow($0) }
        guard !rowSources.isEmpty else { return }

        let homePopup = makeMenuPopup(
            titles: rowSources.map { $0.trimmedNickname.isEmpty ? $0.name : "\($0.name) (\($0.trimmedNickname))" },
            width: 360
        )
        if let activeInputHint, let hintIndex = rowSources.firstIndex(where: { $0.value == activeInputHint }) {
            homePopup.selectItem(at: hintIndex)
        }
        homePopup.frame.origin = NSPoint(x: 0, y: 0)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 56))
        accessory.addSubview(makeLabel(loc("Bu Mac hangi porta bağlı?", "Which port is THIS Mac connected to?"), frame: NSRect(x: 0, y: 32, width: 360, height: 18)))
        accessory.addSubview(homePopup)

        let alert = NSAlert()
        alert.messageText = loc("Adım adım input keşfi", "Guided input discovery")
        alert.informativeText = loc(
            "Ekran kısa süreliğine diğer portlara geçip geri dönecek. Her denemeden sonra ne gördüğün sorulacak.\n\nEkran geri dönmezse monitörün input tuşuyla bu Mac'in portuna dön; keşif kaldığı yerden devam eder.",
            "The screen will briefly switch to other ports and come back. After each try you will be asked what you saw.\n\nIf it doesn't come back, press the monitor's input button to return to this Mac's port; discovery then continues."
        )
        alert.alertStyle = .warning
        alert.accessoryView = accessory
        alert.addButton(withTitle: loc("Başlat", "Start"))
        alert.addButton(withTitle: loc("İptal", "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let home = rowSources[max(0, homePopup.indexOfSelectedItem)]
        let candidates = discoveryCandidates(for: display.title, home: home)
        guard !candidates.isEmpty else { return }

        let session = DiscoverySession(display: display, home: home, candidates: candidates)
        setTestingUIEnabled(false)
        logDiagnostics("Guided discovery started: display=\(display.title) home=\(home.menuLabel) \(home.commandMode.rawValue):\(home.value) candidates=\(candidates.map { $0.command }.joined(separator: ","))")
        runDiscoveryStep(session)
    }

    // Runs on main; each step hops to a background queue for DDC work and back to main for the alert.
    func runDiscoveryStep(_ session: DiscoverySession) {
        guard session.index < session.candidates.count else {
            finishDiscovery(session)
            return
        }

        let candidate = session.candidates[session.index]
        let display = session.display
        logDiagnostics("Discovery try \(session.index + 1)/\(session.candidates.count): \(candidate.command)")

        DispatchQueue.global(qos: .userInitiated).async {
            let before = DDCController.getCurrentInput(displayIndex: display.index)
            let probe = InputSource(name: "Discovery", value: candidate.value, icon: "display", nickname: "", includeInShortcutCycle: false, commandMode: candidate.mode)
            let result = DDCController.setInput(probe, displayIndex: display.index, displayTitle: display.title)

            guard result.status == 0 else {
                DispatchQueue.main.async {
                    logDiagnostics("Discovery stopped: command failed output=\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    self.setTestingUIEnabled(true)
                    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.presentWarningAlert(
                        title: loc("Komut başarısız", "Command failed"),
                        message: output.isEmpty ? loc("m1ddc komutu başarısız oldu.", "The m1ddc command failed.") : output
                    )
                    self.presentDiscoverySummary(session)
                }
                return
            }

            Thread.sleep(forTimeInterval: 3.0)
            var evidence = false
            if !self.monitorStillLocal(display.title) {
                evidence = true
            } else if let after = DDCController.getCurrentInput(displayIndex: display.index), after != before {
                evidence = true
            }
            logDiagnostics("Discovery try evidence: \(candidate.command) switchedAutomatically=\(evidence)")

            let cameBack = self.returnToHome(session)

            DispatchQueue.main.async {
                guard self.window?.isVisible == true else {
                    logDiagnostics("Discovery aborted: settings window closed")
                    self.setTestingUIEnabled(true)
                    return
                }
                if !cameBack { session.stoppedEarly = true }
                self.promptDiscoveryAnswer(session, candidate: candidate, evidence: evidence)
            }
        }
    }

    // Background only. Returns true when the display was back within ~60 s; keeps waiting after that while the window is open.
    func returnToHome(_ session: DiscoverySession) -> Bool {
        let display = session.display
        let start = Date()
        var lastPeerRequest = Date.distantPast

        while true {
            let elapsed = Date().timeIntervalSince(start)
            if monitorStillLocal(display.title) {
                _ = DDCController.setInput(session.home, displayIndex: display.index, displayTitle: display.title)
                Thread.sleep(forTimeInterval: 1.5)
                logDiagnostics("Discovery returned home after \(Int(elapsed)) s")
                return elapsed <= 60
            }

            if elapsed <= 60, Date().timeIntervalSince(lastPeerRequest) >= 20 {
                lastPeerRequest = Date()
                let asked = DispatchQueue.main.sync {
                    self.delegate?.broadcastRemoteSwitch(inputValue: session.home.value, displayTitle: display.title) ?? false
                }
                logDiagnostics("Discovery asked peer to switch back: sent=\(asked)")
            }

            if DispatchQueue.main.sync(execute: { self.window?.isVisible != true }) { return false }
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    func promptDiscoveryAnswer(_ session: DiscoverySession, candidate: DiscoveryCandidate, evidence: Bool) {
        var portNames = SettingsWindowController.discoveryStandardPortNames
        for row in rows {
            let name = row.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !portNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                portNames.append(name)
            }
        }

        let noChangeTitle = loc("Değişiklik yok", "No change")
        let unsureTitle = loc("Değişti, hangi port olduğundan emin değilim", "Switched, not sure which port")
        let popup = makeMenuPopup(titles: [noChangeTitle] + portNames + [unsureTitle], width: 320)
        if evidence { popup.selectItem(at: portNames.count + 1) }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        accessory.addSubview(popup)

        var message = loc("Ekran değişti mi? Monitör hangi portu gösterdi?", "Did the screen switch? Which port did the monitor show?")
        if evidence {
            message += "\n\n" + loc("Otomatik kontrol: monitör bir değişiklik bildirdi.", "Automatic check: the display reported a change.")
        }
        if session.stoppedEarly {
            message += "\n\n" + loc("Monitör 60 sn içinde dönmedi; bu cevaptan sonra keşif özet ile bitecek.", "The display did not return within 60 s; discovery ends with the summary after this answer.")
        }

        let alert = NSAlert()
        alert.messageText = loc("Deneme \(session.index + 1)/\(session.candidates.count): \(candidate.command)", "Try \(session.index + 1)/\(session.candidates.count): \(candidate.command)")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.accessoryView = accessory
        alert.addButton(withTitle: loc("Sonraki", "Next"))
        alert.addButton(withTitle: loc("Bu değeri tekrar dene", "Retry this value"))
        alert.addButton(withTitle: loc("Şimdi bitir", "Finish now"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn, !session.stoppedEarly {
            logDiagnostics("Discovery retry: \(candidate.command)")
            runDiscoveryStep(session)
            return
        }

        let selected = popup.indexOfSelectedItem
        let answer: DiscoveryAnswer
        if selected <= 0 {
            answer = .noChange
        } else if selected > portNames.count {
            answer = .unsure
        } else {
            answer = .port(portNames[selected - 1])
        }
        session.answers.append((candidate: candidate, answer: answer))
        logDiagnostics("Discovery answer: \(candidate.command) -> \(answer)")
        session.index += 1

        if response == .alertThirdButtonReturn || session.stoppedEarly {
            finishDiscovery(session)
        } else {
            runDiscoveryStep(session)
        }
    }

    func finishDiscovery(_ session: DiscoverySession) {
        setTestingUIEnabled(true)
        logDiagnostics("Guided discovery finished: answers=\(session.answers.count)/\(session.candidates.count) stoppedEarly=\(session.stoppedEarly)")
        presentDiscoverySummary(session)
    }

    func rowForPortName(_ name: String) -> InputRowControls? {
        rows.first {
            $0.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func presentDiscoverySummary(_ session: DiscoverySession) {
        var found: [(port: String, candidate: DiscoveryCandidate)] = []
        var unknown: [DiscoveryCandidate] = []
        var noEffect: [DiscoveryCandidate] = []
        for entry in session.answers {
            switch entry.answer {
            case .port(let name): found.append((port: name, candidate: entry.candidate))
            case .unsure: unknown.append(entry.candidate)
            case .noChange: noEffect.append(entry.candidate)
            }
        }
        let untried = session.candidates.filter { candidate in !session.answers.contains(where: { $0.candidate == candidate }) }

        var lines: [String] = [loc("Bu Mac: \(session.home.menuLabel)", "This Mac: \(session.home.menuLabel)")]
        var toApply: [(port: String, candidate: DiscoveryCandidate)] = []
        var seenPorts = Set<String>()
        for entry in found {
            let key = entry.port.lowercased()
            let command = "\(entry.port) — \(entry.candidate.command)"
            if seenPorts.contains(key) {
                lines.append("\(command) " + loc("(ikinci değer, kullanılmaz)", "(second value, not used)"))
            } else if rowForPortName(entry.port) == nil {
                seenPorts.insert(key)
                lines.append("\(command) " + loc("(bu adda satır yok, uygulanmaz)", "(no row with this name, not applied)"))
            } else {
                seenPorts.insert(key)
                toApply.append(entry)
                lines.append(command)
            }
        }
        if !unknown.isEmpty {
            lines.append(loc("Değişti, port bilinmiyor: ", "Switched, port unknown: ") + unknown.map { $0.command }.joined(separator: ", "))
        }
        if !noEffect.isEmpty {
            lines.append(loc("Etkisiz: ", "No effect: ") + noEffect.map { $0.command }.joined(separator: ", "))
        }
        if !untried.isEmpty {
            lines.append(loc("Denenmedi: ", "Not tried: ") + untried.map { $0.command }.joined(separator: ", "))
        }

        let alert = NSAlert()
        alert.messageText = found.isEmpty
            ? loc("Port eşleştirilemedi", "No ports identified")
            : loc("\(seenPorts.count) port eşleştirildi", "Identified \(seenPorts.count) port(s)")
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        if !toApply.isEmpty {
            alert.addButton(withTitle: loc("Listeye Uygula", "Apply to List"))
        }
        alert.addButton(withTitle: loc("Kapat", "Close"))

        let response = alert.runModal()
        guard !toApply.isEmpty, response == .alertFirstButtonReturn else { return }

        for entry in toApply {
            guard let row = rowForPortName(entry.port) else { continue }
            row.valueField.stringValue = "\(entry.candidate.value)"
            if let modeIndex = InputCommandMode.allCases.firstIndex(of: entry.candidate.mode) {
                row.commandModePopup.selectItem(at: modeIndex)
            }
        }
        logDiagnostics("Discovery applied: \(toApply.map { "\($0.port)=\($0.candidate.command)" }.joined(separator: ","))")
        shortcutHelpLabel.stringValue = loc("Keşif sonuçları listeye uygulandı. Kalıcı olması için Kaydet'e bas.", "Discovery results applied to the list. Press Save to keep them.")
    }

    @objc func save() {
        let updatedInputs = rows.indices.compactMap { inputSourceForRow($0) }

        var usedShortcuts: [ShortcutConfig] = shortcutConfig.map { [$0] } ?? []
        for source in updatedInputs {
            guard let hotKey = source.hotKey else { continue }
            if usedShortcuts.contains(hotKey) {
                presentWarningAlert(
                    title: loc("Kısayol çakışması", "Shortcut conflict"),
                    message: loc("\(hotKey.displayString) birden fazla yerde kullanılıyor. Her kısayol tek bir işe atanmalı.", "\(hotKey.displayString) is used more than once. Each shortcut can only have one action.")
                )
                return
            }
            usedShortcuts.append(hotKey)
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
