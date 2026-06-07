import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain." M-07a: pixel font + dark/cyan theme on
/// the existing structure (shuffle, 7-slot grid, and the ornate frame come in
/// M-07b/c/d).
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            goalField
            picker
            stat
            controls
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.pxBG)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            portrait(store.activeCharacter, size: 40)
                .overlay(Circle().stroke(Theme.pxAccent, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.activeCharacter.displayName)
                    .font(.pixel(13, bold: true))
                    .foregroundColor(Theme.pxInk)
                Text(store.statusText.uppercased())
                    .font(.pixel(7))
                    .foregroundColor(store.onDuty ? Theme.pxAccent : Theme.pxDim)
            }
            Spacer()
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SAVING FOR")
                .font(.pixel(7)).tracking(1).foregroundColor(Theme.pxDim)
            TextField("", text: $store.goal,
                      prompt: Text("e.g. Tokyo trip").foregroundColor(Theme.pxDim))
                .textFieldStyle(.plain)
                .font(.pixel(13))
                .foregroundColor(Theme.pxInk)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.pxPanel)
                .overlay(Rectangle().stroke(Theme.pxLine, lineWidth: 1.5))
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PICK YOUR GUARDIAN")
                .font(.pixel(7)).tracking(1).foregroundColor(Theme.pxDim)
            HStack(spacing: 8) {
                ForEach(CharacterID.allCases) { c in
                    Button { store.activeCharacter = c } label: {
                        avatar(c)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(store.activeCharacter == c ? Theme.pxAccent : Theme.pxLine,
                                            lineWidth: store.activeCharacter == c ? 2.5 : 1.5)
                            )
                            .shadow(color: store.activeCharacter == c ? Theme.pxAccent.opacity(0.7) : .clear, radius: 5)
                    }
                    .buttonStyle(.plain)
                    .help(c.displayName)
                }
            }
        }
    }

    private var stat: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.monthlyCount == 0 {
                Text("No catches yet this month.")
                    .font(.pixel(8)).foregroundColor(Theme.pxDim)
            } else {
                Text(store.activeCharacter.brag(count: store.monthlyCount, goal: store.goal))
                    .font(.pixel(9)).foregroundColor(Theme.pxInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = store.streakDays {
                    Text(store.activeCharacter.streak(days: days))
                        .font(.pixel(7)).foregroundColor(Theme.pxDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.pxPanel)
        .overlay(Rectangle().stroke(Theme.pxLine, lineWidth: 1.5))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: onTest) {
                Text("▶ TEST THE CATCH")
                    .font(.pixel(11, bold: true))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.pxAccent)
                    .foregroundColor(Theme.pxBG)
            }
            .buttonStyle(.plain)

            HStack {
                Button(store.isSnoozed ? "WAKE UP" : "SNOOZE 1 HR") {
                    store.isSnoozed ? store.wake() : store.snooze(hours: 1)
                }
                .buttonStyle(.plain)
                .font(.pixel(8)).foregroundColor(Theme.pxInk)
                Spacer()
                Toggle("ON", isOn: $store.enabled)
                    .toggleStyle(.switch).tint(Theme.pxAccent)
                    .font(.pixel(8)).foregroundColor(Theme.pxInk)
            }

            Button("QUIT") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.pixel(7)).foregroundColor(Theme.pxDim)
        }
    }

    // MARK: - Bits

    private func avatar(_ c: CharacterID) -> some View {
        Group {
            if let p = CastAssets.portrait(c) {
                Image(nsImage: p).interpolation(.none).resizable().scaledToFill()
            } else {
                Text(c.placeholderEmoji).font(.system(size: 22))
            }
        }
        .frame(width: 54, height: 54)
        .background(Theme.pxPanel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func portrait(_ c: CharacterID, size: CGFloat) -> some View {
        Group {
            if let p = CastAssets.portrait(c) {
                Image(nsImage: p).interpolation(.none).resizable().scaledToFill()
            } else {
                Text(c.placeholderEmoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .background(Theme.pxPanel)
        .clipShape(Circle())
    }
}
