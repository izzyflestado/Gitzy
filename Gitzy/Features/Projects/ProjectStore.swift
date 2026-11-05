import AppKit
import Observation
import SwiftUI

/// The saved project list, shared by every view. File work (validation, scanning, reading HEAD and the commit log)
/// runs on background tasks; this class only holds the results and talks to the views.
@Observable
final class ProjectStore {
    /// What the list shows, in the order chosen by `sort`.
    private(set) var rows: [ProjectRow] = []
    /// Set only when something did not work and nothing on screen would say so (a folder that is not a repository,
    /// a scan that found nothing, a terminal that would not open). Adding, scanning and removing say nothing
    /// when they succeed. It stays until the next action clears it.
    private(set) var problem: String?
    private(set) var isScanning = false
    /// How the list is ordered. Custom is the order the rows were dragged into, and is where everyone starts.
    /// Remembered between launches.
    private(set) var sort: ProjectSort = .custom

    /// Called whenever the list changes, so the branch widget can match what it detected against the new list.
    @ObservationIgnored var onProjectsChanged: (() -> Void)?

    /// The saved projects in the person's own (dragged) order.
    @ObservationIgnored private var projects: [GitProject]
    /// The same projects as rows, in that same custom order, without any sorting applied.
    @ObservationIgnored private var baseRows: [ProjectRow] = []
    /// When each project last had commit activity, by path, as of the last refresh.
    @ObservationIgnored private var activity: [String: Date] = [:]
    /// Project paths, oldest added first. Kept apart from `projects` because dragging reorders that one.
    @ObservationIgnored private var addedOrder: [String] = []
    @ObservationIgnored private var scanTask: Task<[URL], Never>?
    @ObservationIgnored private var problemTask: Task<Void, Never>?
    private let settings: AppSettings
    private static let defaultsKey = "projectPaths"
    private static let addedKey = "projectAddedOrder"
    private static let sortKey = "projectSort"
    private static let relativeFormatter = RelativeDateTimeFormatter()

    init(settings: AppSettings) {
        self.settings = settings
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        projects = paths.map { GitProject(path: $0) }
        addedOrder = ProjectSorter.reconciledAddedOrder(
            UserDefaults.standard.stringArray(forKey: Self.addedKey) ?? [],
            projects: paths
        )
        if let raw = UserDefaults.standard.string(forKey: Self.sortKey), let saved = ProjectSort(rawValue: raw) {
            sort = saved
        }
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
        addedOrder.removeAll { $0 == project.path }
        baseRows.removeAll { $0.project == project }
        rows.removeAll { $0.project == project }
        activity[project.path] = nil
        save()
        onProjectsChanged?()
    }

    // MARK: Sorting

    /// Picks how the list is ordered. Choosing Custom brings back the order the rows were last dragged into.
    func setSort(_ newValue: ProjectSort) {
        guard newValue != sort else { return }
        sort = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.sortKey)
        rows = arranged()
        // The commit times are as of the last refresh, so read them again before they are trusted for an order.
        if newValue == .lastCommit { Task { await refresh() } }
    }

    /// Called when a row is dragged to a new place. The new order is saved, so it survives a restart.
    /// Projects that are saved but not showing yet (still being read after an add) keep their place at the end.
    /// Dragging while the list is sorted some other way makes the order on screen the Custom order,
    /// so the row stays exactly where it was dropped.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
        let order = rows.map(\.project)
        let notShownYet = projects.filter { !order.contains($0) }
        projects = order + notShownYet
        baseRows = rows
        if sort != .custom {
            sort = .custom
            UserDefaults.standard.set(ProjectSort.custom.rawValue, forKey: Self.sortKey)
        }
        rows = arranged()
        save()
    }

    // MARK: Reading state

    /// Re-reads every project's branch and last commit time from its files.
    func refresh() async {
        let snapshot = projects
        let paths = snapshot.map(\.path)
        let readings: [(ProjectStatus, Date?)] = await Task.detached {
            paths.map { (GitRepositoryService.status(ofProjectAt: $0), GitRepositoryService.lastActivity(ofProjectAt: $0)) }
        }.value
        let statusByPath = Dictionary(zip(paths, readings.map { $0.0 }), uniquingKeysWith: { first, _ in first })
        var found: [String: Date] = [:]
        for (path, reading) in zip(paths, readings) {
            if let date = reading.1 { found[path] = date }
        }
        activity = found
        // Follow the current order, not the snapshot's: the list may have been dragged into a new order
        // (or had a project removed) while the files were being read.
        baseRows = projects.compactMap { project in
            statusByPath[project.path].map { ProjectRow(project: project, status: $0) }
        }
        rows = arranged()
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

    /// Opens the project's page on GitHub in the default browser.
    /// The address was built from a checked owner and repository name when the project was read, so nothing else
    /// from the remote (a password or token in it, say) is ever handed to the browser.
    func openOnGitHub(_ row: ProjectRow) {
        guard let url = row.status.githubURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Private

    /// Adds the folders that are not already listed. Folders already in the list are skipped without a word.
    private func merge(_ folders: [URL]) {
        var known = Set(projects.map(\.path))
        for folder in folders {
            let path = GitRepositoryService.resolvedPath(of: folder)
            if known.insert(path).inserted {
                projects.append(GitProject(path: path))
                addedOrder.append(path)
            }
        }
        save()
        Task { await refresh() }
    }

    private func save() {
        UserDefaults.standard.set(projects.map(\.path), forKey: Self.defaultsKey)
        UserDefaults.standard.set(addedOrder, forKey: Self.addedKey)
    }

    /// `baseRows` in the chosen order, with "3 days ago" added under each one while sorting by last commit.
    private func arranged() -> [ProjectRow] {
        let ordered = ProjectSorter.sorted(baseRows, by: sort, activity: activity, addedOrder: addedOrder)
        return ordered.map { original in
            var row = original
            row.detail = sort == .lastCommit ? detail(for: row) : nil
            return row
        }
    }

    private func detail(for row: ProjectRow) -> String? {
        guard !row.status.isMissing else { return nil }
        guard let date = activity[row.id] else { return "no activity found" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
