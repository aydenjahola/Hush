import HushCore
import HushAudio
import AppKit
import SwiftUI

package struct MixerPopover: View {
    let store: MixerStore
    let updates: UpdateChecker

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overflow = EdgeOverflow()

    package init(store: MixerStore, updates: UpdateChecker) {
        self.store = store
        self.updates = updates
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let message = store.outputSelectionError {
                outputError(message)
            }
            if let update = updates.pendingUpdate {
                UpdateBanner(
                    version: update.version,
                    onDownload: updates.download,
                    onLater: updates.remindLater,
                    onSkip: updates.skipThisVersion)
            }
            if !store.controlsEnabled {
                PermissionBanner()
            }
            if store.strips.isEmpty {
                emptyState
            } else {
                switch appearance.layout {
                case .channelStrips: stripRow
                case .classicRows, .tiles: StripList(store: store, layout: appearance.layout)
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .environment(\.mixerAppearance, appearance)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.strips.map(\.id))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: updates.pendingUpdate?.version)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.outputSelectionError)
        .onChange(of: store.outputSelectionError) { _, message in
            // The error line is easy to miss without sight; VoiceOver speaks it as it appears.
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .background(
            WindowVisibilityObserver { visible in
                if visible {
                    store.popoverDidAppear()
                    updates.refresh()
                } else {
                    store.popoverDidDisappear()
                }
            })
    }

    private var appearance: MixerAppearance { MixerAppearance(store.preferences.appearance) }

    private var header: some View {
        HStack {
            Text(L10n.appName)
                .font(.headline)
                .fixedSize()
                .layoutPriority(1)
            Spacer()
            OutputPicker(store: store)
        }
    }

    /// Why choosing an output failed, under the header for a few seconds.
    private func outputError(_ message: String) -> some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.multicolor)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .transition(.opacity)
    }

    private var stripRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(store.strips) { strip in
                    ChannelStrip(
                        strip: strip,
                        meter: store.meter(for: strip.id),
                        maxPercent: store.maxPercent,
                        isEnabled: store.controlsEnabled && strip.isRunning,
                        actions: StripActions(target: store, id: strip.id))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
        .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
            EdgeOverflow(
                leading: geometry.contentOffset.x > 1,
                trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1)
        } action: { _, newValue in
            overflow = newValue
        }
        .mask { EdgeFadeMask(overflow: overflow) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.zzz")
                .font(.system(size: 28, weight: .light))
            Text(L10n.nothingIsPlaying)
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 236)
    }

    private var footer: some View {
        HStack {
            Text(L10n.playingSummary(count: store.playingCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // SettingsLink is the reliable way to open Settings from a MenuBarExtra in an
            // LSUIElement app; the tap also activates Hush so the window comes to the front.
            SettingsLink {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            .help(L10n.settings)
            .accessibilityLabel(Text(L10n.settings))
            .contextMenu {
                Button(L10n.quit) { NSApp.terminate(nil) }
            }
        }
    }
}

struct EdgeOverflow: Equatable {
    var leading = false
    var trailing = false
}

private struct EdgeFadeMask: View {
    let overflow: EdgeOverflow

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: overflow.leading ? 20 : 0)
            Rectangle().fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: overflow.trailing ? 20 : 0)
        }
    }
}
