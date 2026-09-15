import SwiftUI
import AppKit

/// The menu-bar dropdown — the "brain." Pixel font + dark/cyan theme.
/// Inputs, boxes and buttons use pixel-stepped rounded corners; the avatar grid
/// keeps smooth corners. Stat box is fixed-height so switching characters never
/// resizes the window. The stat is derived from the *current* month on a
/// minute timeline, so a stale count never survives a month boundary
/// (NATIVE-02). PAIR SENSOR shows the bridge token with a COPY button — the
/// one-time, human-mediated handshake with the browser extension (NATIVE-01).
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    @State private var copied = false          // "COPIED" flash after copyToken()

    private let statHeight: CGFloat = 74
    private let slot: CGFloat = 66
    private let slotGap: CGFloat = 8
    private let pxCorner = PixelFrame(step: 2, steps: 3)   // corners for inputs/boxes/buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            goalField
            picker
            shuffleRow
            stat
            pairRow
            controls
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.pxBG)
        .overlay(frameBorder)
    }

    private var frameBorder: some View {
        ZStack {
            PixelFrame(step: 3, steps: 3).stroke(Theme.pxLine, lineWidth: 2)
            PixelFrame(step: 3, steps: 3).stroke(Theme.pxAccent.opacity(0.22), lineWidth: 1).padding(3)
        }
        .padding(5)
        .allowsHitTesting(false)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.menuBar)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 30)
                .foregroundStyle(Theme.pxAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.shuffleMode ? "SHUFFLE" : store.activeCharacter.displayName.uppercased())
                    .font(.pixel(13, bold: true))
                    .foregroundColor(Theme.pxInk)
                    .lineLimit(1)
                Text(store.statusText.uppercased())
                    .font(.pixel(9))
                    .foregroundColor(store.onDuty ? Theme.pxAccent : Theme.pxDim)
            }
            Spacer()
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
            .background(pxCorner.fill(Theme.pxPanel))
            .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))
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

    // Re-evaluated every minute so the month boundary flips the box to "No
    // catches yet" without a stored write; the outer frame stays fixed-height.
    private var stat: some View {
        TimelineView(.everyMinute) { context in
            let count = store.catchCount(inMonthContaining: context.date)
            VStack(alignment: .leading, spacing: 5) {
                if count == 0 {
                    Text("No catches yet this month.")
                        .font(.pixel(10)).foregroundColor(Theme.pxDim)
                } else {
                    Text(store.activeCharacter.brag(count: count, goal: store.goal))
                        .font(.pixel(11)).foregroundColor(Theme.pxInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let last = store.lastCatchDate {
                        Text(store.activeCharacter.streak(days: Store.daysBetween(last, context.date)))
                            .font(.pixel(9)).foregroundColor(Theme.pxDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: statHeight, maxHeight: statHeight, alignment: .topLeading)
        .padding(11)
        .background(pxCorner.fill(Theme.pxPanel))
        .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))
    }

    // PAIR SENSOR — the token box uses the goalField recipe; COPY puts the
    // token on the pasteboard for the extension's Options page. "regenerate"
    // mints a new one and silently unpairs whatever held the old value.
    private var pairRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PAIR SENSOR")
                .font(.pixel(9)).tracking(1).foregroundColor(Theme.pxDim)
            HStack(spacing: 8) {
                Text(store.bridgeToken)
                    .font(.pixel(9))
                    .foregroundColor(Theme.pxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(pxCorner.fill(Theme.pxPanel))
                    .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))
                Button { copyToken() } label: {
                    Text(copied ? "COPIED" : "COPY")
                        .font(.pixel(9, bold: true))
                        .foregroundColor(Theme.pxInk)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("Paste it in the sensor's Options page.")
                    .font(.pixel(8)).foregroundColor(Theme.pxDim)
                Spacer()
                linkButton("regenerate") { store.regenerateBridgeToken() }
            }
        }
    }

    private func copyToken() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(store.bridgeToken, forType: .string)
        Log.info("pair.token_copied", "token copied to pasteboard", ["token_tail": String(store.bridgeToken.suffix(4))])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // Primary — master on/off
            Button { store.enabled.toggle() } label: {
                Text(store.enabled ? "SPENDING ANGEL IS ON" : "SPENDING ANGEL IS OFF")
                    .font(.pixel(12, bold: true))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(store.enabled ? Theme.pxBG : Theme.pxDim)
                    .background(pxCorner.fill(store.enabled ? Theme.pxAccent : Theme.pxPanel))
                    .overlay(pxCorner.stroke(store.enabled ? Color.clear : Theme.pxLine, lineWidth: 1.5))
                    .shadow(color: store.enabled ? Theme.pxAccent.opacity(0.55) : .clear, radius: 8)
            }
            .buttonStyle(.plain)

            // Secondary — Snooze, full-width outlined
            Button { store.isSnoozed ? store.wake() : store.snooze(hours: 1) } label: {
                Text(store.isSnoozed ? "WAKE UP" : "SNOOZE 1 HR")
                    .font(.pixel(11, bold: true))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(Theme.pxInk)
                    .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            // Tertiary — dev Test + Quit as tiny dim links, the version between
            // them so "which build is this?" is answerable from the dropdown.
            HStack {
                linkButton("▶ test", action: onTest)
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.pixel(8)).foregroundColor(Theme.pxDim)
                Spacer()
                linkButton("quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(.top, 2)
        }
    }

    private func linkButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.pixel(8)).foregroundColor(Theme.pxDim)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    private var dieIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Theme.pxInk)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3).offset(x: -4, y: -4)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3)
            Circle().fill(Theme.pxBG).frame(width: 3, height: 3).offset(x: 4, y: 4)
        }
        .frame(width: 16, height: 16)
    }

    // Avatars + "?" slots keep smooth corners (Ian: leave the avatars out).
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
