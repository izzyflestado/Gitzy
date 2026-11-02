import SwiftUI

/// The "Sort: Name" menu that sits between the action buttons and the project list.
struct ProjectSortBar: View {
    let store: ProjectStore

    var body: some View {
        HStack {
            Menu {
                Picker("Sort by", selection: Binding(get: { store.sort }, set: { store.setSort($0) })) {
                    ForEach(ProjectSort.allCases) { option in
                        Text(option.menuLabel).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Sort: \(store.sort.shortLabel)", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .font(.system(size: 11))
        .transaction { $0.animation = nil }
    }
}
