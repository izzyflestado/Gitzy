import SwiftUI

/// The keyboard shortcuts part of Settings: an on/off switch and the keys for each action.
/// The keys are shown here and stored as settings. Editing them in this window comes later.
struct ShortcutsSettingsSection: View {
    let controller: ShortcutController

    var body: some View {
        Section("Keyboard shortcuts") {
            Toggle("Use global shortcuts", isOn: enabledBinding)

            ForEach(ShortcutAction.allCases) { action in
                LabeledContent(action.title) {
                    keyCap(controller.shortcut(for: action).display)
                }
                if let problem = controller.problems[action] {
                    note(problem, isProblem: true)
                }
            }
        }
    }

    // MARK: Pieces

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.isEnabled },
            set: { controller.setEnabled($0) }
        )
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(controller.isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    private func note(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
