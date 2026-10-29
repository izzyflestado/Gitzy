import AppKit
import Observation

/// The saved project list, shared by every view. File work (validation, scanning, reading HEAD)
/// runs on background tasks; this class only holds the results and talks to the views.
@Observable
final class ProjectStore {
    private(set) var rows: [ProjectRow] = []
    /// Set only when something did not work and nothing on screen would say so (a folder that is not a repository,
    /// a scan that found nothing, a terminal that would not open). Adding, scanning and removing say nothing
    /// when they succeed. It stays until the next action clears it.
    private(set) var problem: String?
    private(set) var isScanning = false

    /// Called whenever the list changes, so the branch widget can match what it detected against the new list.
    @ObservationIgnored var onProjectsChanged: (() -> Void)?

    @ObservationIgnored private var projects: [GitProject]
    @ObservationIgnored private var scanTask: Task<[URL], Never>?
    @ObservationIgnored private var problemTask: Task<Void, Never>?
    private let settings: AppSettings
    private static let defaultsKey = "projectPaths"

    init(settings: AppSettings) {
        self.settings = settings
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        projects = paths.map { GitProject(path: $0) }
        Task { await refresh() }
    }

    // MARK: Adding and removing

    func clearProblem() {
        problemTask?.cancel()
        problemTask = nil
        problem = nil
    }

    /// Shows a problem and removes it by itself after 5 seconds. A newer problem restarts the 5 seconds.
    private func show(_ text: String) {
        problemTask?.cancel()
        problem = text
        problemTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            problem = nil
        }
    }

    func addProject(at folder: URL) {
        problem = nil
        Task {
            let isRepository = await Task.detached { GitRepositoryService.isRepository(at: folder) }.value
            guard isRepository else {
                show("\(folder.lastPathComponent) is not a Git repository.")
                return
            }
            merge([folder])
        }
    }

    func scan(folder: URL) {
        scanTask?.cancel()
        problem = nil
        isScanning = true

        let work = Task.detached(priority: .utility) {
            ProjectScanner.scan(root: folder)
        }
        scanTask = work

        Task {
            let found = await work.value
            guard scanTask == work else { return }   // stopped, or replaced by a newer scan
            scanTask = nil
            isScanning = false
            if found.isEmpty {
                show("No Git projects found in \(folder.lastPathComponent).")
            } else {
                merge(found)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    /// Removes the project from Gitzy only. The folder itself is never touched.
    func remove(_ project: GitProject) {
        problem = nil
        projects.removeAll { $0 == project }
        rows.removeAll { $0.project == project }
        save()
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
        problem = nil
        guard let app = settings.terminalAppURL else {
            show("No terminal app found.")
            return
        }
        Task {
            do {
                let folder = URL(fileURLWithPath: project.path, isDirectory: true)
                _ = try await NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                show("Could not open \(app.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private

    /// Adds the folders that are not already listed. Folders already in the list are skipped without a word.
    private func merge(_ folders: [URL]) {
        var known = Set(projects.map(\.path))
        for folder in folders {
            let path = GitRepositoryService.resolvedPath(of: folder)
            if known.insert(path).inserted {
                projects.append(GitProject(path: path))
            }
        }
        save()
        Task { await refresh() }
    }

    private func save() {
        UserDefaults.standard.set(projects.map(\.path), forKey: Self.defaultsKey)
    }
}
