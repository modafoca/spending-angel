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
        VStack(alignment: .leading, spacing: 18) {
            if showingSettings {
                settings
            } else {
                header
                goalField
                picker
                shuffleRow
                stat
                controls
            }
        }
        .padding(18)
        .frame(width: 332)
        .background(Theme.pxBG)
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.menuBar)
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 20, height: 28)
                .foregroundColor(Theme.pxAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text("Spending Angel").font(.pixel(11, bold: true))
                Text(store.statusText).font(.system(size: 12))
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
                .font(.system(size: 17, weight: .medium))
                .textFieldStyle(.plain)
                .padding(12)
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
        }
    }

    private var shuffleRow: some View {
        HStack {
            Text("Surprise me").font(.system(size: 13))
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
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text(count == 0 ? "No catches yet this month." : "\(count) \(count == 1 ? "catch" : "catches") this month")
                    .font(.system(size: 11)).foregroundColor(Theme.pxDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundColor(Theme.pxDim)
            .help("Plays a character, even while off or snoozed")
        }
    }

    private func controlLabel(_ title: String, filled: Bool) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundColor(filled ? Theme.pxBG : Theme.pxInk)
            .background(pxCorner.fill(filled ? Theme.pxAccent : Theme.pxPanel))
            .overlay(pxCorner.stroke(filled ? Color.clear : Theme.pxLine, lineWidth: 1))
            .contentShape(Rectangle())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    showingSettings = false
                    showingCode = false
                } label: {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 13))
                        .frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundColor(Theme.pxAccent)
                Spacer()
                Text("Settings").font(.system(size: 15, weight: .semibold))
            }
            Divider().overlay(Theme.pxLine)
            VStack(alignment: .leading, spacing: 10) {
                Text("Browser connection").font(.system(size: 16, weight: .semibold))
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
                        .buttonStyle(.plain).font(.system(size: 12))
                        .foregroundColor(Theme.pxAccent)
                        .accessibilityLabel(showingCode ? "Hide connection code" : "Show connection code")
                }
                .padding(12).background(pxCorner.fill(Theme.pxPanel))
                Button { copyToken() } label: { controlLabel(copied ? "Copied" : "Copy code", filled: true) }
                    .buttonStyle(.plain)
                Button("Replace connection code…") { confirmingNewCode = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Theme.pxDim)
                    .padding(.top, 2)
            }
            Divider().overlay(Theme.pxLine)
            HStack {
                Text("Version \(AppInfo.version)").font(.system(size: 11)).foregroundColor(Theme.pxDim)
                Spacer()
                Button("Quit Spending Angel") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Theme.pxDim)
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
        .frame(width: 68, height: 68)
        .background(Theme.pxPanel)
        .opacity(selected ? 1 : 0.55)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke(selected ? Theme.pxAccent : Theme.pxLine, lineWidth: selected ? 2 : 1))
    }
}
