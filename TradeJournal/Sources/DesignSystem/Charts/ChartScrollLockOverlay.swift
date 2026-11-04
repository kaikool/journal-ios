import SwiftUI
import UIKit

// MARK: - Unified Native UIKit Chart Interaction & Scroll-Lock Controller
// Handles all chart touch interactions in a single native UIKit layer:
// 1. Instantaneous parent UIScrollView lock on touch-down (zero outer page scroll interference)
// 2. Zone-isolated 1-finger Pan:
//    - Right Price Axis strip (58pt): vertical price scale zoom
//    - Bottom Time Axis strip (28pt): horizontal time scale zoom
//    - Main Canvas: smooth 2D horizontal time & vertical price panning
// 3. 2-finger Pinch Zoom anchored at the finger midpoint
// 4. Long-press Crosshair scrubbing (pauses panning while scrubbing)
// 5. Double-tap Reset to auto-fit latest candles
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
        view.onDoubleTapReset = onDoubleTapReset
    }
}

public final class ScrollLockContainerView: UIView, UIGestureRecognizerDelegate {
    private enum DragZone {
        case canvas
        case priceAxis
        case timeAxis
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
    public var onDoubleTapReset: (() -> Void)?

    private weak var cachedScrollView: UIScrollView?
    private var lockGesture: ChartScrollLockGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?
    private var longPressGesture: UILongPressGestureRecognizer?
    private var doubleTapGesture: UITapGestureRecognizer?

    private var activeDragZone: DragZone = .canvas
    private var lastPanTranslation: CGPoint = .zero
    private var isCrosshairActive: Bool = false

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

        // 2. 1-Finger Pan (Zone-Isolated: Canvas 2D Pan vs Right Price Axis vs Bottom Time Axis)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = self
        addGestureRecognizer(pan)
        self.panGesture = pan

        // 3. 2-Finger Pinch Zoom
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
        self.pinchGesture = pinch

        // 4. Long-Press Crosshair Scrub
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.32
        longPress.allowableMovement = 10
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delegate = self
        addGestureRecognizer(longPress)
        self.longPressGesture = longPress

        // 5. Double-Tap Reset
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delaysTouchesBegan = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        self.doubleTapGesture = doubleTap
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Never allow outer UIScrollView pan gesture to compete with our chart gestures
        if let sv = cachedScrollView ?? findParentScrollView(),
           otherGestureRecognizer.view === sv {
            return false
        }
        return true
    }

    @objc private func handleLockGesture(_ recognizer: ChartScrollLockGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lockParentScroll(true)
        case .ended, .cancelled, .failed:
            lockParentScroll(false)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        // Do not pan while pinching with 2 fingers or scrubbing crosshair
        if let pinch = pinchGesture, (pinch.state == .began || pinch.state == .changed), pinch.numberOfTouches >= 2 {
            return
        }
        if isCrosshairActive {
            return
        }

        switch recognizer.state {
        case .began:
            let startLoc = recognizer.location(in: self)
            lastPanTranslation = .zero
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
                onCanvasPan?(dx, dy, t.x, t.y)
            }

        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
            onPanEnded?()

        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let scale = recognizer.scale
            recognizer.scale = 1.0
            let focal = recognizer.location(in: self)
            onPinchZoom?(scale, focal.x)
        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isCrosshairActive = true
            let loc = recognizer.location(in: self)
            onCrosshairChanged?(loc.x)
        case .changed:
            let loc = recognizer.location(in: self)
            onCrosshairChanged?(loc.x)
        case .ended, .cancelled, .failed:
            isCrosshairActive = false
            onCrosshairChanged?(nil)
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            isCrosshairActive = false
            onCrosshairChanged?(nil)
            onDoubleTapReset?()
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
            cachedScrollView?.isScrollEnabled = true
            onTouchStateChanged?(false)
        }
    }

    deinit {
        cachedScrollView?.isScrollEnabled = true
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
