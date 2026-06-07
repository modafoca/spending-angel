import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain," in the brand's cream/navy/gold sticker
/// look. Portrait, editable goal, character picker (real art), brag stat +
/// streak, snooze, on/off.
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
        .background(Theme.cream)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            portrait(store.activeCharacter, size: 42)
                .overlay(Circle().stroke(Theme.gold, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.activeCharacter.displayName)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Theme.navy)
                Text(store.statusText)
                    .font(.caption)
                    .foregroundColor(Theme.navy.opacity(store.onDuty ? 0.7 : 0.4))
            }
            Spacer()
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SAVING FOR")
                .font(.caption2.weight(.bold))
                .foregroundColor(Theme.navy.opacity(0.6))
            TextField("e.g. Tokyo trip", text: $store.goal)
                .textFieldStyle(.plain)
                .foregroundColor(Theme.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.navy.opacity(0.25), lineWidth: 1.5))
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(CharacterID.allCases) { c in
                Button { store.activeCharacter = c } label: {
                    avatar(c)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(store.activeCharacter == c ? Theme.gold : Theme.navy.opacity(0.15),
                                        lineWidth: store.activeCharacter == c ? 3 : 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(c.displayName)
            }
        }
    }

    private var stat: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.monthlyCount == 0 {
                Text("No catches yet this month. So far, so good.")
                    .font(.callout)
                    .foregroundColor(Theme.navy.opacity(0.6))
            } else {
                Text(store.activeCharacter.brag(count: store.monthlyCount, goal: store.goal))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = store.streakDays {
                    Text(store.activeCharacter.streak(days: days))
                        .font(.caption)
                        .foregroundColor(Theme.navy.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.18)))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button(action: onTest) {
                Text("▶︎ Test the catch")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.gold)
                    .foregroundColor(Theme.navy)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)

            HStack {
                Button(store.isSnoozed ? "Wake up" : "Snooze 1 hr") {
                    store.isSnoozed ? store.wake() : store.snooze(hours: 1)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.navy)
                Spacer()
                Toggle("On", isOn: $store.enabled)
                    .toggleStyle(.switch)
                    .tint(Theme.gold)
                    .foregroundColor(Theme.navy)
            }
            .font(.callout)

            Divider()

            Button("Quit Spending Angel") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(Theme.navy.opacity(0.5))
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(Color.white)
        .clipShape(Circle())
    }
}
