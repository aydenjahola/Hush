import AppKit
import Observation
import SwiftUI

/// Thin level bar: green, turning yellow in the top 30%. Hidden (space kept) when inactive.
///
/// Cheap by design (R-C1). SwiftUI only lays it out; the live level goes straight from the
/// strip's `StripMeter` to a Core Animation layer transform in `MeterLayerView`, so a meter tick
/// re-renders no SwiftUI view at all, not even this one.
struct LevelMeter: View {
    let meter: StripMeter
    var axis: Axis = .vertical
    /// False for muted or idle apps: the meter keeps its space but shows nothing.
    var isActive = true

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        MeterLayerView(meter: meter, style: .bar(axis), increasedContrast: contrast == .increased)
            .frame(width: axis == .vertical ? 3 : nil, height: axis == .horizontal ? 3 : nil)
            .opacity(isActive ? 1 : 0)
            .accessibilityHidden(true)
    }
}

/// Tiles: a soft green wash from the leading edge whose length follows the live level.
struct LevelGlow: View {
    let meter: StripMeter
    var isActive = true
    var increasedContrast = false

    var body: some View {
        MeterLayerView(meter: meter, style: .glow, increasedContrast: increasedContrast)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum MeterStyle: Equatable {
    case bar(Axis)
    case glow
}

/// Hosts `MeterLayer` and keeps it subscribed to one `StripMeter`.
struct MeterLayerView: NSViewRepresentable {
    let meter: StripMeter
    let style: MeterStyle
    let increasedContrast: Bool

    func makeNSView(context: Context) -> MeterNSView {
        MeterNSView(style: style)
    }

    func updateNSView(_ view: MeterNSView, context: Context) {
        view.style = style
        view.increasedContrast = increasedContrast
        view.bind(meter)
    }

    static func dismantleNSView(_ view: MeterNSView, coordinator: ()) {
        view.bind(nil)
    }
}

/// A track and a full-size coloured fill inside a clipping layer sized to the level, so the
/// colour bands stay put while more or less of them shows. A level change sets one layer frame
/// with implicit animations off: no SwiftUI update, no redraw. (A clip rather than a layer mask,
/// because masks don't render in `cacheDisplay` snapshots.)
final class MeterNSView: NSView {
    var style: MeterStyle { didSet { if style != oldValue { updateColors(); needsLayout = true } } }
    var increasedContrast = false { didSet { if increasedContrast != oldValue { updateColors() } } }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for layer in [track, reveal, fill] { layer.contentsScale = scale }
        layer?.contentsScale = scale
    }

    private let track = CALayer()
    private let fill = CAGradientLayer()
    private let reveal = CALayer()  // clips `fill` to the level
    private weak var meter: StripMeter?
    /// Bumped on every bind so a stale observation callback from a previous meter is ignored.
    private var generation = 0
    private(set) var displayedFraction: CGFloat = 0

    init(style: MeterStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        reveal.masksToBounds = true
        reveal.anchorPoint = .zero
        reveal.addSublayer(fill)
        fill.anchorPoint = .zero
        layer?.addSublayer(track)
        layer?.addSublayer(reveal)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    func bind(_ meter: StripMeter?) {
        guard meter !== self.meter else { return }
        self.meter = meter
        generation += 1
        observe(generation)
    }

    /// Reads the level under observation tracking; the change handler (called before the value
    /// changes) re-reads on the next main-actor turn and re-subscribes.
    private func observe(_ token: Int) {
        guard token == generation, let meter else { return }
        let fraction = withObservationTracking {
            meter.fraction
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(token) }
        }
        apply(CGFloat(fraction))
    }

    private func apply(_ fraction: CGFloat) {
        displayedFraction = fraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reveal.bounds = revealBounds(fraction)
        CATransaction.commit()
    }

    /// Layer space is y-up with the origin at the bottom-left, so a clip anchored at the origin
    /// grows up from the bottom (vertical) or right from the leading edge.
    private func revealBounds(_ fraction: CGFloat) -> CGRect {
        let size = bounds.size
        return switch style {
        case .bar(.vertical): CGRect(x: 0, y: 0, width: size.width, height: (size.height * fraction).rounded())
        default: CGRect(x: 0, y: 0, width: (size.width * fraction).rounded(), height: size.height)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = self.bounds
        layer?.cornerRadius = style == .glow ? 0 : min(bounds.width, bounds.height) / 2
        track.frame = bounds
        reveal.position = .zero
        reveal.bounds = revealBounds(displayedFraction)
        fill.position = .zero
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch style {
            case .bar(let axis):
                track.backgroundColor = NSColor.labelColor.withAlphaComponent(increasedContrast ? 0.3 : 0.1).cgColor
                fill.colors = [NSColor.systemGreen, .systemGreen, .systemYellow, .systemYellow].map(\.cgColor)
                fill.locations = [0, 0.7, 0.7, 1]
                // Layer space is y-up: (0.5, 0) is the bottom edge.
                fill.startPoint = axis == .vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
                fill.endPoint = axis == .vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
            case .glow:
                track.backgroundColor = nil
                let green = NSColor.systemGreen
                // Fainter than the volume fill and fading to nothing, so it never reads as a second fill.
                let alpha: CGFloat = increasedContrast ? (dark ? 0.4 : 0.34) : (dark ? 0.15 : 0.12)
                fill.colors = [green.withAlphaComponent(alpha), green.withAlphaComponent(0)].map(\.cgColor)
                fill.locations = [0, 1]
                fill.startPoint = CGPoint(x: 0, y: 0.5)
                fill.endPoint = CGPoint(x: 1, y: 0.5)
            }
        }
        CATransaction.commit()
    }
}
