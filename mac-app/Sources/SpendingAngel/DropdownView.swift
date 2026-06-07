import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain." M-07a: pixel font + dark/cyan theme.
/// The active guardian reads via a cyan wash + ring in the picker (no redundant
/// header avatar). The stat box is a FIXED height so switching characters never
/// resizes/shifts the window.
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    /// Constant height for the stat box — fits the longest brag + streak so the
    /// window never changes size when you switch character or land your first catch.
    private let statHeight: CGFloat = 74

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            goalField
            picker
            stat
            controls
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.pxBG)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("SPENDING ANGEL")
                .font(.pixel(13, bold: true))
                .foregroundColor(Theme.pxInk)
            Spacer()
            Text(store.statusText.uppercased())
                .font(.pixel(9))
                .foregroundColor(store.onDuty ? Theme.pxAccent : Theme.pxDim)
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SAVING FOR")
                .font(.pixel(9)).tracking(1).foregroundColor(Theme.pxDim)
            ZStack(alignment: .leading) {
                if store.goal.isEmpty {
                    Text("e.g. Tokyo trip")                       // visible placeholder
                        .font(.pixel(14))
                        .foregroundColor(Theme.pxInk.opacity(0.4))
                        .allowsHitTesting(false)
                }
                TextField("", text: $store.goal)
                    .textFieldStyle(.plain)
                    .font(.pixel(14))
                    .foregroundColor(Theme.pxInk)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(Theme.pxPanel)
            .overlay(Rectangle().stroke(Theme.pxLine, lineWidth: 1.5))
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PICK YOUR GUARDIAN")
                .font(.pixel(9)).tracking(1).foregroundColor(Theme.pxDim)
            HStack(spacing: 9) {
                ForEach(CharacterID.allCases) { c in
                    Button { store.activeCharacter = c } label: { avatar(c) }
                        .buttonStyle(.plain)
                        .help(c.displayName)
                }
            }
        }
    }

    private var stat: some View {
        VStack(alignment: .leading, spacing: 5) {
            if store.monthlyCount == 0 {
                Text("No catches yet this month.")
                    .font(.pixel(10)).foregroundColor(Theme.pxDim)
            } else {
                Text(store.activeCharacter.brag(count: store.monthlyCount, goal: store.goal))
                    .font(.pixel(11)).foregroundColor(Theme.pxInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = store.streakDays {
                    Text(store.activeCharacter.streak(days: days))
                        .font(.pixel(9)).foregroundColor(Theme.pxDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: statHeight, maxHeight: statHeight, alignment: .topLeading)  // FIXED height
        .padding(11)
        .background(Theme.pxPanel)
        .overlay(Rectangle().stroke(Theme.pxLine, lineWidth: 1.5))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: onTest) {
                Text("▶ TEST THE CATCH")
                    .font(.pixel(12, bold: true))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.pxAccent)
                    .foregroundColor(Theme.pxBG)
            }
            .buttonStyle(.plain)

            HStack {
                Button(store.isSnoozed ? "WAKE UP" : "SNOOZE 1 HR") {
                    store.isSnoozed ? store.wake() : store.snooze(hours: 1)
                }
                .buttonStyle(.plain)
                .font(.pixel(10)).foregroundColor(Theme.pxInk)
                Spacer()
                Toggle("ON", isOn: $store.enabled)
                    .toggleStyle(.switch).tint(Theme.pxAccent)
                    .font(.pixel(10)).foregroundColor(Theme.pxInk)
            }

            // subtle pill
            Button("QUIT") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.pixel(9)).foregroundColor(Theme.pxDim)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .overlay(Capsule().stroke(Theme.pxLine, lineWidth: 1.5))
        }
    }

    // MARK: - Bits

    private func avatar(_ c: CharacterID) -> some View {
        let selected = store.activeCharacter == c
        return Group {
            if let p = CastAssets.portrait(c) {
                Image(nsImage: p).interpolation(.none).resizable().scaledToFill()
            } else {
                Text(c.placeholderEmoji).font(.system(size: 24))
            }
        }
        .frame(width: 58, height: 58)
        .background(Theme.pxPanel)
        .opacity(selected ? 1 : 0.4)            // dim the unselected; no wash on the selected
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Theme.pxAccent : Theme.pxLine, lineWidth: selected ? 2.5 : 1.5)
        )
        .shadow(color: selected ? Theme.pxAccent.opacity(0.75) : .clear, radius: 6)
    }
}
