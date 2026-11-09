import Foundation
import ProsperCore

/// The agent's hold on the rules. It reads the shared file, merges it add-only
/// with what it already knows and with the extension's copy, writes the result
/// back, and sends it to the extension. A file edited by hand to drop a lock
/// or the guard is restored within seconds.
final class AgentRules {
    private(set) var rules: MacRules = .empty
    private(set) var active: ActiveRules
    private(set) var filterStatus: FilterStatus?
    private(set) var filterError: String?
    private let client = FilterClient()
    private var watcher: DispatchSourceFileSystemObject?
    private var lastPushedRevision = -1
    private var lastPush = Date.distantPast
    var onChange: (() -> Void)?

    init() {
        let now = Date()
        rules = MacStore.loadRules(at: now)
        active = ActiveRules(rules: rules, at: now)
        watchFolder()
        // Get back anything the extension holds that our files lost.
        client.rules { [weak self] theirs in
            guard let theirs else { return }
            DispatchQueue.main.async { self?.absorb(theirs) }
        }
    }

    /// Called every couple of seconds and whenever the folder changes.
    func refresh() {
        let now = Date()
        let fromDisk = MacStore.loadRules(mergingWith: rules, at: now)
        let previous = rules
        rules = fromDisk
        if rules != previous || now >= active.validUntil {
            active = ActiveRules(rules: rules, at: now)
            onChange?()
        }
        // Put back anything a hand edit removed.
        if MacStore.read(MacRules.self, from: MacStore.rulesURL) != rules {
            try? MacStore.updateRules(at: now) { $0.merged(with: self.rules, at: now) }
        }
        if rules.revision != lastPushedRevision || now.timeIntervalSince(lastPush) > 15 {
            push()
        }
    }

    private func absorb(_ theirs: MacRules) {
        let now = Date()
        let merged = rules.merged(with: theirs, at: now)
        guard merged != rules else { return }
        agentLog.info("Restored rules from the extension (revision \(theirs.revision))")
        rules = merged
        try? MacStore.updateRules(at: now) { $0.merged(with: merged, at: now) }
        active = ActiveRules(rules: rules, at: now)
        onChange?()
    }

    private func push() {
        let sent = rules
        lastPush = Date()
        client.apply(sent) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let status):
                    self.filterStatus = status
                    self.filterError = nil
                    self.lastPushedRevision = sent.revision
                case .failure(let error):
                    self.filterStatus = nil
                    self.filterError = error.localizedDescription
                }
            }
        }
    }

    private func watchFolder() {
        let fd = open(MacStore.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
