import Foundation

/// How the Projects list is ordered. The raw values are what gets saved, so do not rename them.
nonisolated enum ProjectSort: String, CaseIterable, Identifiable, Sendable {
    /// The order the person dragged the rows into. This is the default, and what the list was before sorting existed.
    case custom
    case name
    case recentlyAdded
    case lastCommit

    var id: String { rawValue }

    /// Shown in the menu.
    var menuLabel: String {
        switch self {
        case .custom: return "Custom (drag to arrange)"
        case .name: return "Name (A–Z)"
        case .recentlyAdded: return "Recently added"
        case .lastCommit: return "Last commit"
        }
    }

    /// Shown on the sort button itself, after "Sort:".
    var shortLabel: String {
        switch self {
        case .custom: return "Custom"
        case .name: return "Name"
        case .recentlyAdded: return "Recently added"
        case .lastCommit: return "Last commit"
        }
    }
}

/// Puts project rows in order. Pure: it reads nothing from disk.
nonisolated enum ProjectSorter {
    /// - rows: in the person's own (dragged) order. That is what `.custom` returns, unchanged.
    /// - activity: a project's path to when it last had commit activity. Projects without a date go last.
    /// - addedOrder: project paths, oldest added first. It is kept apart from `rows` because dragging reorders the rows.
    static func sorted(_ rows: [ProjectRow], by sort: ProjectSort, activity: [String: Date], addedOrder: [String]) -> [ProjectRow] {
        switch sort {
        case .custom:
            return rows

        case .name:
            return rows.sorted { byName($0, $1) }

        case .recentlyAdded:
            var rank: [String: Int] = [:]
            for (index, path) in addedOrder.enumerated() { rank[path] = index }
            return rows.sorted { first, second in
                // A project the add-order has never heard of counts as the oldest.
                let one = rank[first.id] ?? -1
                let two = rank[second.id] ?? -1
                return one == two ? byName(first, second) : one > two
            }

        case .lastCommit:
            return rows.sorted { first, second in
                switch (activity[first.id], activity[second.id]) {
                case let (one?, two?):
                    return one == two ? byName(first, second) : one > two
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return byName(first, second)
                }
            }
        }
    }

    /// Makes a saved add-order match the projects that exist now: entries for projects that are gone are dropped,
    /// duplicates are dropped, and projects the saved order never listed are added at the end, in their current order.
    /// (That last part is also how a list saved before this feature existed gets its first add-order.)
    static func reconciledAddedOrder(_ saved: [String], projects: [String]) -> [String] {
        let existing = Set(projects)
        var seen = Set<String>()
        var result: [String] = []
        for path in saved where existing.contains(path) && seen.insert(path).inserted {
            result.append(path)
        }
        for path in projects where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }

    /// Like Finder: ignores case, and puts "app2" before "app10". Equal names fall back to the path, so the order is always the same.
    private static func byName(_ first: ProjectRow, _ second: ProjectRow) -> Bool {
        let order = first.project.name.localizedStandardCompare(second.project.name)
        if order != .orderedSame { return order == .orderedAscending }
        return first.project.path < second.project.path
    }
}
