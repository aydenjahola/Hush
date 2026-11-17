import AppKit
import SwiftUI

/// Holds the strip-row edge overflow. Replaces `@State` (SwiftUI macro plugin unavailable under CLT).
@MainActor
final class PopoverModel: ObservableObject {
    @Published var overflow = EdgeOverflow()
}

public struct MixerPopover: View {
    let store: MixerStore

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = PopoverModel()

    public init(store: MixerStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !store.controlsEnabled {
                PermissionBanner()
            }
            if store.strips.isEmpty {
                emptyState
            } else {
                stripRow
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.strips.map(\.id))
        .background(
            WindowVisibilityObserver { visible in
                if visible { store.popoverDidAppear() } else { store.popoverDidDisappear() }
            })
    }

    private var header: some View {
        HStack {
            Text("Hush")
                .font(.headline)
            Spacer()
            Label(store.outputDevice?.name ?? "No Output", systemImage: "hifispeaker.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel("Output: \(store.outputDevice?.name ?? "none")")
        }
    }

    private var stripRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(store.strips) { strip in
                    ChannelStrip(
                        strip: strip,
                        meterLevel: store.meterLevels[strip.id],
                        maxPercent: store.maxPercent,
                        isEnabled: store.controlsEnabled && strip.isRunning,
                        onPercentChange: { store.setPercent($0, for: strip.id) },
                        onReset: { store.resetVolume(for: strip.id) },
                        onToggleMute: { store.toggleMute(for: strip.id) })
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
            model.overflow = newValue
        }
        .mask { EdgeFadeMask(overflow: model.overflow) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.zzz")
                .font(.system(size: 28, weight: .light))
            Text("Nothing is playing")
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 236)
    }

    private var footer: some View {
        HStack {
            Text(playingSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            .contextMenu {
                Button("Quit Hush") { NSApp.terminate(nil) }
            }
        }
    }

    private var playingSummary: String {
        switch store.playingCount {
        case 0: "No apps playing"
        case 1: "1 app playing"
        case let count: "\(count) apps playing"
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
