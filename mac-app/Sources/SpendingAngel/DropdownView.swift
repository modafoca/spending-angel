import SwiftUI
import AppKit

/// Everyday controls stay on the front; browser setup lives behind Settings.
/// The goal, roster, and catch count keep their existing Store behavior.
struct DropdownView: View {
    @ObservedObject var store: Store
    var onTest: () -> Void

    @State private var showingSettings = false
    @State private var showingCode = false
    @State private var copied = false
    @State private var confirmingNewCode = false
    private let pxCorner = PixelFrame(step: 2, steps: 3)

    var body: some View {
        // Keep both pages in the layout so navigation never resizes/recenters
        // the MenuBarExtra window. Only the visible page can receive input.
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                header
                goalField
                picker
                shuffleRow
                stat
                controls
            }
            .opacity(showingSettings ? 0 : 1)
            .disabled(showingSettings)
            .allowsHitTesting(!showingSettings)
            .accessibilityHidden(showingSettings)

            settings
                .opacity(showingSettings ? 1 : 0)
                .disabled(!showingSettings)
                .allowsHitTesting(showingSettings)
                .accessibilityHidden(!showingSettings)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.pxBG)
        .overlay(frameBorder)
        .foregroundColor(Theme.pxInk)
        .preferredColorScheme(.dark)
        .confirmationDialog("Replace your connection code?", isPresented: $confirmingNewCode) {
            Button("Replace code", role: .destructive) {
                store.regenerateBridgeToken()
                copied = false
                showingCode = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your browser will disconnect until you paste the new code in its Settings.")
        }
    }

    private var frameBorder: some View {
        ZStack {
            PixelFrame(step: 3, steps: 3).stroke(Theme.pxLine, lineWidth: 2)
            PixelFrame(step: 3, steps: 3).stroke(Theme.pxAccent.opacity(0.22), lineWidth: 1).padding(3)
        }
        .padding(5)
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.menuBar)
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 20, height: 28)
                .foregroundColor(Theme.pxAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text("Spending Angel").font(.pixel(11, bold: true))
                Text(store.statusText).font(.pixel(9))
                    .foregroundColor(store.onDuty ? Theme.pxAccent : Theme.pxDim)
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape").font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.pxDim)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAVING FOR").font(.pixel(9)).foregroundColor(Theme.pxDim)
            TextField("e.g. Tokyo trip", text: $store.goal)
                .font(.pixel(14))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(pxCorner.fill(Theme.pxPanel))
                .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1))
                .accessibilityLabel("Saving for")
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR GUARDIAN").font(.pixel(9)).foregroundColor(Theme.pxDim)
            HStack(spacing: 8) {
                ForEach(CharacterID.allCases) { character in
                    Button { store.activeCharacter = character } label: { avatar(character) }
                        .buttonStyle(.plain)
                        .help(character.displayName)
                        .accessibilityLabel(character.displayName)
                        .accessibilityValue(store.activeCharacter == character ? "Selected" : "")
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    Text("?").font(.pixel(24))
                        .foregroundColor(Theme.pxDim.opacity(0.65))
                        .frame(width: 66, height: 66)
                        .background(Theme.pxPanel.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.pxLine.opacity(0.65), lineWidth: 1))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Four more guardians coming soon")
            .help("More guardians coming soon")
        }
    }

    private var shuffleRow: some View {
        HStack {
            Text("Surprise me").font(.pixel(9))
            Spacer()
            Toggle("Surprise me", isOn: $store.shuffleMode)
                .toggleStyle(PixelToggleStyle()).labelsHidden()
                .accessibilityLabel("Surprise me")
                .accessibilityValue(store.shuffleMode ? "On" : "Off")
        }
    }

    private var stat: some View {
        TimelineView(.everyMinute) { context in
            let count = store.catchCount(inMonthContaining: context.date)
            VStack(alignment: .leading, spacing: 6) {
                Text(count == 0 ? "Your next good decision starts here."
                     : store.activeCharacter.brag(count: count, goal: store.goal))
                    .font(.pixel(11))
                    .fixedSize(horizontal: false, vertical: true)
                Text(count == 0 ? "No catches yet this month." : "\(count) \(count == 1 ? "catch" : "catches") this month")
                    .font(.pixel(9)).foregroundColor(Theme.pxDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(pxCorner.fill(Theme.pxPanel))
        .overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { store.enabled.toggle() } label: {
                    controlLabel(store.enabled ? "Turn off" : "Turn on", filled: !store.enabled)
                }
                .buttonStyle(.plain)
                Button { store.isSnoozed ? store.wake() : store.snooze(hours: 1) } label: {
                    controlLabel(store.isSnoozed ? "Wake up" : "Snooze 1h", filled: false)
                }
                .buttonStyle(.plain)
                .disabled(!store.enabled)
                .opacity(store.enabled ? 1 : 0.45)
            }
            Button(action: onTest) {
                Label("Try character", systemImage: "play.fill")
                    .font(.pixel(9))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundColor(Theme.pxDim)
            .help("Plays a character, even while off or snoozed")
        }
    }

    private func controlLabel(_ title: String, filled: Bool) -> some View {
        Text(title).font(.pixel(11, bold: true))
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundColor(filled ? Theme.pxBG : Theme.pxInk)
            .background(pxCorner.fill(filled ? Theme.pxAccent : Theme.pxPanel))
            .overlay(pxCorner.stroke(filled ? Color.clear : Theme.pxLine, lineWidth: 1))
            .contentShape(Rectangle())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    showingSettings = false
                    showingCode = false
                } label: {
                    Label("Back", systemImage: "chevron.left").font(.pixel(10))
                        .frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundColor(Theme.pxAccent)
                Spacer()
                Text("Settings").font(.pixel(13, bold: true))
            }
            Divider().overlay(Theme.pxLine)
            VStack(alignment: .leading, spacing: 10) {
                Text("Browser connection").font(.pixel(11, bold: true))
                Text("Copy this code into Spending Angel’s Settings in Chrome. You only need to do this once.")
                    .font(.system(size: 13)).foregroundColor(Theme.pxDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(showingCode ? store.bridgeToken : "•••• •••• …" + String(store.bridgeToken.suffix(4)))
                        .font(.system(size: 11, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button(showingCode ? "Hide" : "Show") { showingCode.toggle() }
                        .buttonStyle(.plain).font(.pixel(9))
                        .foregroundColor(Theme.pxAccent)
                        .accessibilityLabel(showingCode ? "Hide connection code" : "Show connection code")
                }
                .padding(12).background(pxCorner.fill(Theme.pxPanel))
                Button { copyToken() } label: { controlLabel(copied ? "Copied" : "Copy code", filled: true) }
                    .buttonStyle(.plain)
                Button("Replace connection code…") { confirmingNewCode = true }
                    .buttonStyle(.plain).font(.pixel(9)).foregroundColor(Theme.pxDim)
                    .padding(.top, 2)
            }
            Divider().overlay(Theme.pxLine)
            HStack {
                Text("Version \(AppInfo.version)").font(.pixel(9)).foregroundColor(Theme.pxDim)
                Spacer()
                Button("Quit Spending Angel") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.pixel(9)).foregroundColor(Theme.pxDim)
            }
        }
    }

    private func copyToken() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(store.bridgeToken, forType: .string)
        Log.info("pair.token_copied", "code copied to pasteboard", ["token_tail": String(store.bridgeToken.suffix(4))])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func avatar(_ character: CharacterID) -> some View {
        let selected = store.activeCharacter == character
        return Group {
            if let portrait = CastAssets.portrait(character) {
                Image(nsImage: portrait).interpolation(.none).resizable().scaledToFill()
            } else {
                Text(character.placeholderEmoji).font(.system(size: 26))
            }
        }
        .frame(width: 66, height: 66)
        .background(Theme.pxPanel)
        .opacity(selected ? 1 : 0.4)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selected ? Theme.pxAccent : Theme.pxLine, lineWidth: selected ? 2.5 : 1))
        .shadow(color: selected ? Theme.pxAccent.opacity(0.35) : .clear, radius: 6)
    }
}
