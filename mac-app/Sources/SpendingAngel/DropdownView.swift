import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain." Portrait, editable goal, character
/// picker, snooze, on/off. (The brag stat + streak land in M-04.)
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    private let navy = Color(red: 0.11, green: 0.18, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            goalField
            picker
            controls
        }
        .padding(16)
        .frame(width: 288)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(store.activeCharacter.placeholderEmoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.activeCharacter.displayName)
                    .font(.headline)
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(store.onDuty ? Color.green : .secondary)
            }
            Spacer()
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SAVING FOR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Tokyo trip", text: $store.goal)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(CharacterID.allCases) { c in
                Button { store.activeCharacter = c } label: {
                    Text(c.placeholderEmoji)
                        .font(.system(size: 24))
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(store.activeCharacter == c
                                      ? Color.accentColor.opacity(0.22)
                                      : Color.gray.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(store.activeCharacter == c ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .help(c.displayName)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button(action: onTest) {
                Text("▶︎ Test the catch").frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            HStack {
                if store.isSnoozed {
                    Button("Wake up") { store.wake() }
                } else {
                    Button("Snooze 1 hr") { store.snooze(hours: 1) }
                }
                Spacer()
                Toggle("On", isOn: $store.enabled)
                    .toggleStyle(.switch)
            }

            Divider()

            Button("Quit Spending Angel") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
