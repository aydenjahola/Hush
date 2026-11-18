import HushCore
import SwiftUI

/// Classic rows and tiles: apps stacked vertically, scrolling once there are more than about six.
struct StripList: View {
    let store: MixerStore
    let layout: MixerLayout

    @Environment(\.mixerAppearance) private var appearance
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: spacing) {
                ForEach(store.strips) { strip in
                    StripListRow(
                        layout: layout,
                        strip: strip,
                        meter: store.meter(for: strip.id),
                        maxPercent: store.maxPercent,
                        isEnabled: store.controlsEnabled && strip.isRunning,
                        actions: StripActions(target: store, id: strip.id))
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                contentHeight = $0
            }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(contentHeight > 0 ? contentHeight : estimatedHeight, maxHeight))
    }

    private var spacing: CGFloat {
        switch layout {
        case .tiles: appearance.isCompact ? 4 : 6
        default: appearance.isCompact ? 0 : 2
        }
    }

    private var rowHeight: CGFloat {
        switch layout {
        case .tiles: appearance.isCompact ? 32 : 40
        default: appearance.isCompact ? 26 : 30
        }
    }

    private var estimatedHeight: CGFloat {
        let count = CGFloat(store.strips.count)
        return count * rowHeight + max(count - 1, 0) * spacing
    }

    /// Six rows and a half, so the cut-off row hints that the list scrolls.
    private var maxHeight: CGFloat {
        6.5 * rowHeight + 6 * spacing
    }
}

/// One app in the vertical layouts.
struct StripListRow: View {
    let layout: MixerLayout
    let strip: MixerStore.Strip
    let meter: StripMeter
    let maxPercent: Int
    let isEnabled: Bool
    let actions: StripActions

    var body: some View {
        switch layout {
        case .tiles:
            VolumeTile(strip: strip, meter: meter, maxPercent: maxPercent, isEnabled: isEnabled, actions: actions)
        case .classicRows, .channelStrips:
            ClassicRow(strip: strip, meter: meter, maxPercent: maxPercent, isEnabled: isEnabled, actions: actions)
        }
    }
}
