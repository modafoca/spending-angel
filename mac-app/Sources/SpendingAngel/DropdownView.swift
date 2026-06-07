import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain." Pixel font + dark/cyan theme.
/// Guardian grid is 4 characters + 4 "?" coming-soon slots (image-swappable),
/// sized to fill the column. Stat box is fixed-height so switching characters
/// never resizes the window.
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    private let statHeight: CGFloat = 74
    private let slot: CGFloat = 66      // 4 × 66 + 3 × 8 = 288 = full inner width
    private let slotGap: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            goalField
            picker
            shuffleRow
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
                    Text("e.g. Tokyo trip")
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
        VStack(alignment: .leading, spacing: slotGap) {
            Text("PICK YOUR GUARDIAN")
                .font(.pixel(9)).tracking(1).foregroundColor(Theme.pxDim)
            HStack(spacing: slotGap) {
                ForEach(CharacterID.allCases) { c in
                    Button { store.activeCharacter = c } label: { avatar(c) }
                        .buttonStyle(.plain)
                        .help(c.displayName)
                }
            }
            HStack(spacing: slotGap) {
                ForEach(0..<4, id: \.self) { _ in comingSoonSlot }
            }
        }
    }

    private var shuffleRow: some View {
        HStack(spacing: 9) {
            Toggle("", isOn: $store.shuffleMode)
                .toggleStyle(PixelToggleStyle()).labelsHidden()
            Text("SHAKE IT UP")
                .font(.pixel(9)).foregroundColor(Theme.pxInk)
            dieIcon
            Spacer()
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
        .frame(maxWidth: .infinity, minHeight: statHeight, maxHeight: statHeight, alignment: .topLeading)
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

            HStack(spacing: 8) {
                Button(store.isSnoozed ? "WAKE UP" : "SNOOZE 1 HR") {
                    store.isSnoozed ? store.wake() : store.snooze(hours: 1)
                }
                .buttonStyle(.plain)
                .font(.pixel(10)).foregroundColor(Theme.pxInk)
                Spacer()
                Text("ON").font(.pixel(10)).foregroundColor(Theme.pxInk)
                Toggle("", isOn: $store.enabled)
                    .toggleStyle(PixelToggleStyle()).labelsHidden()
            }

            Button("QUIT") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.pixel(9)).foregroundColor(Theme.pxDim)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .overlay(Capsule().stroke(Theme.pxLine, lineWidth: 1.5))
        }
    }

    // MARK: - Bits

    /// A small drawn die (white, three pips) — replaces the unreadable 🎲 emoji.
    private var dieIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Theme.pxInk)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3).offset(x: -4, y: -4)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3).offset(x: 4, y: 4)
        }
        .frame(width: 16, height: 16)
    }

    private func avatar(_ c: CharacterID) -> some View {
        let selected = store.activeCharacter == c
        return Group {
            if let p = CastAssets.portrait(c) {
                Image(nsImage: p).interpolation(.none).resizable().scaledToFill()
            } else {
                Text(c.placeholderEmoji).font(.system(size: 26))
            }
        }
        .frame(width: slot, height: slot)
        .background(Theme.pxPanel)
        .opacity(selected ? 1 : 0.4)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Theme.pxAccent : Theme.pxLine, lineWidth: selected ? 2.5 : 1.5)
        )
        .shadow(color: selected ? Theme.pxAccent.opacity(0.75) : .clear, radius: 6)
    }

    private var comingSoonSlot: some View {
        Text("?")
            .font(.pixel(24, bold: true))
            .foregroundColor(Theme.pxDim)
            .frame(width: slot, height: slot)
            .background(Theme.pxPanel)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.pxLine, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            )
            .opacity(0.5)
    }
}
