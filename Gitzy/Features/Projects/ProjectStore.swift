import AppKit
import Observation

/// The saved project list, shared by every view. File work (validation, scanning, reading HEAD)
/// runs on background tasks; this class only holds the results and talks to the views.
@Observable
final class ProjectStore {
    private(set) var rows: [ProjectRow] = []
    private(set) var message = "Add a project or scan a folder."
    private(set) var isScanning = false

    /// Called whenever the list changes, so the branch widget can match what it detected against the new list.
    @ObservationIgnored var onProjectsChanged: (() -> Void)?

    @ObservationIgnored private var projects: [GitProject]
    @ObservationIgnored private var scanTask: Task<[URL], Never>?
    private let settings: AppSettings
    private static let defaultsKey = "projectPaths"

    init(settings: AppSettings) {
        self.settings = settings
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        projects = paths.map { GitProject(path: $0) }
        Task { await refresh() }
    }

    // MARK: Adding and removing

    func addProject(at folder: URL) {
        Task {
            let isRepository = await Task.detached { GitRepositoryService.isRepository(at: folder) }.value
            guard isRepository else {
                message = "\(folder.lastPathComponent) is not a Git repository."
                return
            }
            let result = merge([folder])
            message = result.added == 1
                ? "Added \(folder.lastPathComponent)."
                : "\(folder.lastPathComponent) is already in the list."
        }
    }

    func scan(folder: URL) {
        scanTask?.cancel()
        isScanning = true
        message = "Scanning \(folder.lastPathComponent)…"

        let work = Task.detached(priority: .utility) {
            ProjectScanner.scan(root: folder)
        }
        scanTask = work

        Task {
            let found = await work.value
            guard scanTask == work else { return }   // stopped, or replaced by a newer scan
            scanTask = nil
            isScanning = false
            let result = merge(found)
            let count = found.count == 1 ? "1 repository" : "\(found.count) repositories"
            message = "Found \(count): \(result.added) new, \(result.duplicates) already in the list."
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        message = "Scan stopped."
    }

    /// Removes the project from Gitzy only. The folder itself is never touched.
    func remove(_ project: GitProject) {
        projects.removeAll { $0 == project }
        rows.removeAll { $0.project == project }
        save()
        message = "Removed \(project.name) from Gitzy. Its files were not touched."
        onProjectsChanged?()
    }

    // MARK: Reading state

    /// Re-reads every project's branch from its files.
    func refresh() async {
        let snapshot = projects
        let paths = snapshot.map(\.path)
        let statuses = await Task.detached {
            paths.map { GitRepositoryService.status(ofProjectAt: $0) }
        }.value
        rows = zip(snapshot, statuses).map { ProjectRow(project: $0, status: $1) }
        onProjectsChanged?()
    }

    // MARK: Row actions

    /// Opens the project folder itself in Finder, so its contents are showing.
    func openInFinder(_ project: GitProject) {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true))
    }

    /// Hands the folder to the chosen terminal app. No AppleScript, so no extra permission.
    func openInTerminal(_ project: GitProject) {
        guard let app = settings.terminalAppURL else {
            message = "No terminal app found. Choose one below."
            return
        }
        Task {
            do {
                let folder = URL(fileURLWithPath: project.path, isDirectory: true)
                _ = try await NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                message = "Could not open \(app.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Private

    /// Adds folders that are not already listed. Returns how many were new and how many were duplicates.
    private func merge(_ folders: [URL]) -> (added: Int, duplicates: Int) {
        var known = Set(projects.map(\.path))
        var added = 0
        var duplicates = 0
        for folder in folders {
            let path = GitRepositoryService.resolvedPath(of: folder)
            if known.insert(path).inserted {
                projects.append(GitProject(path: path))
                added += 1
            } else {
                duplicates += 1
            }
        }
        save()
        Task { await refresh() }
        return (added, duplicates)
    }

    private func save() {
        UserDefaults.standard.set(projects.map(\.path), forKey: Self.defaultsKey)
    }
}
