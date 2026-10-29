import SwiftUI

/// The Widget tab: show or hide the widget, where it sits, and how it looks.
struct WidgetTabView: View {
    let widget: BranchWidgetController
    let settings: AppSettings

    /// Every press of Reset adds one full turn (anticlockwise, like the arrow), which makes the icon spin once.
    @State private var resetTurns = 0

    var body: some View {
        // Scrolls only if a larger text size ever makes this taller than the popover.
        // "No animation" is applied piece by piece below, not here, so the Reset icon is free to spin.
        ScrollView {
            VStack(spacing: 14) {
                visibilityButton
                    .transaction { $0.animation = nil }
                positionRow
                    .transaction { $0.animation = nil }
                Divider()
                customization
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Show / hide

    private var visibilityButton: some View {
        Button {
            widget.setVisible(!widget.isVisible)
        } label: {
            Label(widget.isVisible ? "Hide Widget" : "Show Widget",
                  systemImage: widget.isVisible ? "eye.slash" : "eye")
                .frame(width: 150)
        }
        .buttonStyle(.borderedProminent)
        .tint(widget.isVisible ? Color.accentColor : Color.gray)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    // MARK: Position

    private var positionRow: some View {
        HStack {
            Text("Position")
            Spacer()
            Picker("Position", selection: Binding(
                get: { settings.widgetPosition },
                set: { widget.setPosition($0) }
            )) {
                ForEach(WidgetPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
    }

    // MARK: Customization

    private var customization: some View {
        VStack(spacing: 12) {
            header
            sizeRow
                .transaction { $0.animation = nil }
            HStack(alignment: .top, spacing: 28) {
                ColorWheelPicker(title: "Background", color: settings.widgetBackground) { widget.setBackground($0) }
                ColorWheelPicker(title: "Text", color: settings.widgetTextColor) { widget.setTextColor($0) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Customization")
                .font(.system(size: 13, weight: .semibold))

            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .rotationEffect(.degrees(Double(resetTurns) * -360))
                    .animation(.linear(duration: 1), value: resetTurns)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Reset size and colours to default")
            .accessibilityLabel("Reset customization")

            Spacer()
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Text("Size")
            Slider(
                value: Binding(get: { settings.widgetScale }, set: { widget.setScale($0) }),
                in: AppSettings.widgetScaleRange,
                step: 0.05
            )
            Text("\(Int((settings.widgetScale * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        // The size can only be seen on the widget, so it is only editable while the widget is showing.
        .disabled(!widget.isVisible)
        .help(widget.isVisible ? "Make the widget smaller or bigger" : "Show the widget to change its size")
    }

    // MARK: Actions

    private func reset() {
        resetTurns += 1
        widget.resetAppearance()
    }
}
