import SwiftUI
import UIKit

// MARK: - TradingView-Grade Native UIKit Chart Interaction & Kinetic Engine
// Handles all chart touch interactions in a single native UIKit layer:
// 1. Instantaneous parent UIScrollView lock on touch-down (zero outer page scroll interference)
// 2. 60/120fps CADisplayLink kinetic momentum (inertial scrolling on flick release, instant catch on touch)
// 3. Zone-isolated 1-finger Pan:
//    - Right Price Axis strip (58pt): vertical price scale zoom (switches Price Scale to Manual)
//    - Bottom Time Axis strip (28pt): horizontal time scale zoom anchored to right viewport
//    - Main Canvas: directional intent lock (pure horizontal pan in Auto mode, 2D free pan in Manual mode or vertical drag)
// 4. 2-finger Pinch Zoom:
//    - Horizontal/diagonal pinch: zooms Time Scale anchored at finger midpoint + tracks 2-finger pan
//    - Vertical pinch: zooms Price Scale
// 5. Long-press 2D Crosshair scrubbing (tracks both X bar index and Y exact price)
// 6. Zone-aware Double-tap Reset (Price Axis resets Auto Price Scale; Canvas/Time Axis resets full viewport)
public struct ChartScrollLockOverlay: UIViewRepresentable {
    public var rightAxisWidth: CGFloat = 58
    public var bottomAxisHeight: CGFloat = 28
    public var onTouchStateChanged: ((Bool) -> Void)?
    public var onCanvasPan: ((_ dx: CGFloat, _ dy: CGFloat, _ totalDx: CGFloat, _ totalDy: CGFloat) -> Void)?
    public var onPanEnded: (() -> Void)?
    public var onPriceAxisZoom: ((_ dy: CGFloat) -> Void)?
    public var onTimeAxisZoom: ((_ dx: CGFloat) -> Void)?
    public var onPinchZoom: ((_ scaleDelta: CGFloat, _ focalX: CGFloat) -> Void)?
    public var onCrosshairChanged: ((_ x: CGFloat?) -> Void)?
    public var onCrosshairPointChanged: ((_ point: CGPoint?) -> Void)?
    public var onPriceAxisDoubleTap: (() -> Void)?
    public var onDoubleTapReset: (() -> Void)?

    public init(
        rightAxisWidth: CGFloat = 58,
        bottomAxisHeight: CGFloat = 28,
        onTouchStateChanged: ((Bool) -> Void)? = nil,
        onCanvasPan: ((_ dx: CGFloat, _ dy: CGFloat, _ totalDx: CGFloat, _ totalDy: CGFloat) -> Void)? = nil,
        onPanEnded: (() -> Void)? = nil,
        onPriceAxisZoom: ((_ dy: CGFloat) -> Void)? = nil,
        onTimeAxisZoom: ((_ dx: CGFloat) -> Void)? = nil,
        onPinchZoom: ((_ scaleDelta: CGFloat, _ focalX: CGFloat) -> Void)? = nil,
        onCrosshairChanged: ((_ x: CGFloat?) -> Void)? = nil,
        onCrosshairPointChanged: ((_ point: CGPoint?) -> Void)? = nil,
        onPriceAxisDoubleTap: (() -> Void)? = nil,
        onDoubleTapReset: (() -> Void)? = nil
    ) {
        self.rightAxisWidth = rightAxisWidth
        self.bottomAxisHeight = bottomAxisHeight
        self.onTouchStateChanged = onTouchStateChanged
        self.onCanvasPan = onCanvasPan
        self.onPanEnded = onPanEnded
        self.onPriceAxisZoom = onPriceAxisZoom
        self.onTimeAxisZoom = onTimeAxisZoom
        self.onPinchZoom = onPinchZoom
        self.onCrosshairChanged = onCrosshairChanged
        self.onCrosshairPointChanged = onCrosshairPointChanged
        self.onPriceAxisDoubleTap = onPriceAxisDoubleTap
        self.onDoubleTapReset = onDoubleTapReset
    }

    public func makeUIView(context: Context) -> ScrollLockContainerView {
        let view = ScrollLockContainerView()
        applyCallbacks(to: view)
        return view
    }

    public func updateUIView(_ uiView: ScrollLockContainerView, context: Context) {
        applyCallbacks(to: uiView)
    }

    private func applyCallbacks(to view: ScrollLockContainerView) {
        view.rightAxisWidth = rightAxisWidth
        view.bottomAxisHeight = bottomAxisHeight
        view.onTouchStateChanged = onTouchStateChanged
        view.onCanvasPan = onCanvasPan
        view.onPanEnded = onPanEnded
        view.onPriceAxisZoom = onPriceAxisZoom
        view.onTimeAxisZoom = onTimeAxisZoom
        view.onPinchZoom = onPinchZoom
        view.onCrosshairChanged = onCrosshairChanged
        view.onCrosshairPointChanged = onCrosshairPointChanged
        view.onPriceAxisDoubleTap = onPriceAxisDoubleTap
        view.onDoubleTapReset = onDoubleTapReset
    }
}

public final class ScrollLockContainerView: UIView, UIGestureRecognizerDelegate {
    private enum DragZone {
        case canvas
        case priceAxis
        case timeAxis
    }

    private enum CanvasDragIntent {
        case undecided
        case horizontalOnly
        case free2D
    }

    public var rightAxisWidth: CGFloat = 58
    public var bottomAxisHeight: CGFloat = 28
    public var onTouchStateChanged: ((Bool) -> Void)?
    public var onCanvasPan: ((_ dx: CGFloat, _ dy: CGFloat, _ totalDx: CGFloat, _ totalDy: CGFloat) -> Void)?
    public var onPanEnded: (() -> Void)?
    public var onPriceAxisZoom: ((_ dy: CGFloat) -> Void)?
    public var onTimeAxisZoom: ((_ dx: CGFloat) -> Void)?
    public var onPinchZoom: ((_ scaleDelta: CGFloat, _ focalX: CGFloat) -> Void)?
    public var onCrosshairChanged: ((_ x: CGFloat?) -> Void)?
    public var onCrosshairPointChanged: ((_ point: CGPoint?) -> Void)?
    public var onPriceAxisDoubleTap: (() -> Void)?
    public var onDoubleTapReset: (() -> Void)?

    private weak var cachedScrollView: UIScrollView?
    private var lockGesture: ChartScrollLockGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?
    private var longPressGesture: UILongPressGestureRecognizer?
    private var doubleTapGesture: UITapGestureRecognizer?
    private var singleTapGesture: UITapGestureRecognizer?

    private var activeDragZone: DragZone = .canvas
    private var canvasDragIntent: CanvasDragIntent = .undecided
    private var lastPanTranslation: CGPoint = .zero
    private var lastPinchFocal: CGPoint = .zero
    private var isCrosshairActive: Bool = false

    // Kinetic inertia state
    private var displayLink: CADisplayLink?
    private var inertiaVelocity: CGPoint = .zero
    private var lastInertiaTimestamp: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true

        // 1. Immediate Touch-Down Outer ScrollView Lock
        let lock = ChartScrollLockGestureRecognizer(target: self, action: #selector(handleLockGesture(_:)))
        lock.cancelsTouchesInView = false
        lock.delaysTouchesBegan = false
        lock.delaysTouchesEnded = false
        lock.delegate = self
        addGestureRecognizer(lock)
        self.lockGesture = lock

        // 2. 1-Finger Pan (Zone-Isolated: Canvas vs Right Price Axis vs Bottom Time Axis)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = self
        addGestureRecognizer(pan)
        self.panGesture = pan

        // 3. 2-Finger Pinch Zoom (Time Axis & Vertical Price Axis)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
        self.pinchGesture = pinch

        // 4. Long-Press 2D Crosshair Scrub
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.28
        longPress.allowableMovement = 9
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delegate = self
        addGestureRecognizer(longPress)
        self.longPressGesture = longPress

        // 5. Double-Tap Reset (Zone-Aware)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delaysTouchesBegan = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        self.doubleTapGesture = doubleTap

        // 6. Single-Tap (Dismisses active crosshair or toggles bottom-right Auto Price Scale badge)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delaysTouchesBegan = false
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        addGestureRecognizer(singleTap)
        self.singleTapGesture = singleTap
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if let sv = cachedScrollView ?? findParentScrollView(),
           otherGestureRecognizer.view === sv {
            return false
        }
        return true
    }

    @objc private func handleLockGesture(_ recognizer: ChartScrollLockGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopInertia()
            lockParentScroll(true)
        case .ended, .cancelled, .failed:
            lockParentScroll(false)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if let pinch = pinchGesture, (pinch.state == .began || pinch.state == .changed), pinch.numberOfTouches >= 2 {
            return
        }
        if isCrosshairActive {
            return
        }

        switch recognizer.state {
        case .began:
            stopInertia()
            let startLoc = recognizer.location(in: self)
            lastPanTranslation = .zero
            canvasDragIntent = .undecided

            if startLoc.x >= bounds.width - rightAxisWidth {
                activeDragZone = .priceAxis
            } else if startLoc.y >= bounds.height - bottomAxisHeight {
                activeDragZone = .timeAxis
            } else {
                activeDragZone = .canvas
            }

        case .changed:
            let t = recognizer.translation(in: self)
            let dx = t.x - lastPanTranslation.x
            let dy = t.y - lastPanTranslation.y
            lastPanTranslation = t

            switch activeDragZone {
            case .priceAxis:
                onPriceAxisZoom?(dy)
            case .timeAxis:
                onTimeAxisZoom?(dx)
            case .canvas:
                if canvasDragIntent == .undecided {
                    let dist = hypot(t.x, t.y)
                    if dist >= 6.0 {
                        // TradingView directional lock: horizontal swipe stays pure horizontal unless clearly vertical
                        if abs(t.y) > abs(t.x) * 1.35 {
                            canvasDragIntent = .free2D
                        } else {
                            canvasDragIntent = .horizontalOnly
                        }
                    }
                }
                let effectiveTotalDy: CGFloat = (canvasDragIntent == .free2D) ? t.y : 0
                onCanvasPan?(dx, dy, t.x, effectiveTotalDy)
            }

        case .ended:
            let velocity = recognizer.velocity(in: self)
            lastPanTranslation = .zero
            if activeDragZone == .canvas {
                let speed = hypot(velocity.x, velocity.y)
                if speed > 90 {
                    startInertia(velocity: velocity)
                } else {
                    onPanEnded?()
                }
            } else {
                onPanEnded?()
            }

        case .cancelled, .failed:
            lastPanTranslation = .zero
            onPanEnded?()

        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopInertia()
            lastPinchFocal = recognizer.location(in: self)
            let scale = recognizer.scale
            recognizer.scale = 1.0
            onPinchZoom?(scale, lastPinchFocal.x)

        case .changed:
            let scale = recognizer.scale
            recognizer.scale = 1.0
            let focal = recognizer.location(in: self)
            let focalDx = focal.x - lastPinchFocal.x
            let focalDy = focal.y - lastPinchFocal.y
            lastPinchFocal = focal

            // Check if 2 fingers are oriented vertically to scale price, or horizontally to scale time
            if recognizer.numberOfTouches >= 2 {
                let p0 = recognizer.location(ofTouch: 0, in: self)
                let p1 = recognizer.location(ofTouch: 1, in: self)
                let spanX = abs(p1.x - p0.x)
                let spanY = abs(p1.y - p0.y)
                if spanY > spanX * 2.0 {
                    // Vertical 2-finger pinch zooms Price Scale
                    let syntheticDy = (1.0 - scale) * 160.0
                    onPriceAxisZoom?(syntheticDy)
                    return
                }
            }

            if abs(focalDx) > 0.2 || abs(focalDy) > 0.2 {
                onCanvasPan?(focalDx, focalDy, focalDx, 0)
            }
            onPinchZoom?(scale, focal.x)

        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopInertia()
            isCrosshairActive = true
            let loc = recognizer.location(in: self)
            let pt = CGPoint(x: loc.x, y: max(0, loc.y - 24))
            onCrosshairChanged?(loc.x)
            onCrosshairPointChanged?(pt)

        case .changed:
            let loc = recognizer.location(in: self)
            let pt = CGPoint(x: loc.x, y: max(0, loc.y - 24))
            onCrosshairChanged?(loc.x)
            onCrosshairPointChanged?(pt)

        case .ended, .cancelled, .failed:
            isCrosshairActive = false
            onCrosshairChanged?(nil)
            onCrosshairPointChanged?(nil)

        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        stopInertia()
        isCrosshairActive = false
        onCrosshairChanged?(nil)
        onCrosshairPointChanged?(nil)

        let loc = recognizer.location(in: self)
        if loc.x >= bounds.width - rightAxisWidth {
            if let priceReset = onPriceAxisDoubleTap {
                priceReset()
            } else {
                onDoubleTapReset?()
            }
        } else {
            onDoubleTapReset?()
        }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        stopInertia()
        let loc = recognizer.location(in: self)
        // Bottom-right corner "A" (Auto Price Scale) button hit area
        if loc.x >= bounds.width - rightAxisWidth && loc.y >= bounds.height - (bottomAxisHeight + 24) {
            onPriceAxisDoubleTap?()
            return
        }
        if isCrosshairActive {
            isCrosshairActive = false
            onCrosshairChanged?(nil)
            onCrosshairPointChanged?(nil)
        }
    }

    // MARK: - 60/120fps CADisplayLink Kinetic Deceleration
    private func startInertia(velocity: CGPoint) {
        stopInertia()
        // Cap initial velocity for controlled TradingView feel
        let maxSpeed: CGFloat = 2400
        let vx = max(-maxSpeed, min(maxSpeed, velocity.x))
        let vy = (canvasDragIntent == .free2D) ? max(-maxSpeed, min(maxSpeed, velocity.y)) : 0
        inertiaVelocity = CGPoint(x: vx, y: vy)
        lastInertiaTimestamp = CACurrentMediaTime()

        let proxy = WeakDisplayLinkProxy(target: self)
        let link = CADisplayLink(target: proxy, selector: #selector(WeakDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func stopInertia() {
        displayLink?.invalidate()
        displayLink = nil
        inertiaVelocity = .zero
    }

    fileprivate func stepInertia(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(max(0.001, min(0.05, now - lastInertiaTimestamp)))
        lastInertiaTimestamp = now

        let dx = inertiaVelocity.x * dt
        let dy = inertiaVelocity.y * dt

        onCanvasPan?(dx, dy, 0, 0)

        // Exponential decay (0.915 per 60fps frame)
        let decay = pow(0.915, dt * 60.0)
        inertiaVelocity.x *= decay
        inertiaVelocity.y *= decay

        if hypot(inertiaVelocity.x, inertiaVelocity.y) < 18.0 {
            stopInertia()
            onPanEnded?()
        }
    }

    private func lockParentScroll(_ locked: Bool) {
        if locked {
            if cachedScrollView == nil || cachedScrollView?.window == nil {
                cachedScrollView = findParentScrollView()
            }
            cachedScrollView?.isScrollEnabled = false
            onTouchStateChanged?(true)
        } else {
            cachedScrollView?.isScrollEnabled = true
            onTouchStateChanged?(false)
        }
    }

    private func findParentScrollView() -> UIScrollView? {
        var curr: UIView? = self.superview
        while let current = curr {
            if let sv = current as? UIScrollView {
                return sv
            }
            curr = current.superview
        }
        return nil
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopInertia()
            cachedScrollView?.isScrollEnabled = true
            onTouchStateChanged?(false)
        }
    }

    deinit {
        displayLink?.invalidate()
        cachedScrollView?.isScrollEnabled = true
    }
}

private final class WeakDisplayLinkProxy {
    weak var target: ScrollLockContainerView?

    init(target: ScrollLockContainerView) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let target = target else {
            link.invalidate()
            return
        }
        target.stepInertia(link)
    }
}

final class ChartScrollLockGestureRecognizer: UIGestureRecognizer {
    private var activeTouches: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.formUnion(touches)
        if state == .possible {
            state = .began
        } else {
            state = .changed
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            state = .ended
        } else {
            state = .changed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            state = .cancelled
        } else {
            state = .changed
        }
    }

    override func reset() {
        super.reset()
        activeTouches.removeAll()
    }
}
