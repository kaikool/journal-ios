import SwiftUI
import UIKit

// MARK: - Native UIKit Touch Observer for Locking Outer ScrollView
// When a user touches down anywhere on the chart, this observer immediately disables
// the parent UIScrollView so that horizontal and vertical chart panning/zooming
// never competes with or triggers the outer page scroll.
public struct ChartScrollLockOverlay: UIViewRepresentable {
    public let onTouchStateChanged: ((Bool) -> Void)?

    public init(onTouchStateChanged: ((Bool) -> Void)? = nil) {
        self.onTouchStateChanged = onTouchStateChanged
    }

    public func makeUIView(context: Context) -> ScrollLockContainerView {
        let view = ScrollLockContainerView()
        view.onTouchStateChanged = onTouchStateChanged
        return view
    }

    public func updateUIView(_ uiView: ScrollLockContainerView, context: Context) {
        uiView.onTouchStateChanged = onTouchStateChanged
    }
}

public final class ScrollLockContainerView: UIView, UIGestureRecognizerDelegate {
    public var onTouchStateChanged: ((Bool) -> Void)?
    private weak var cachedScrollView: UIScrollView?
    private var lockGesture: ChartScrollLockGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let gesture = ChartScrollLockGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.delegate = self
        addGestureRecognizer(gesture)
        self.lockGesture = gesture
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleGesture(_ recognizer: ChartScrollLockGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lockParentScroll(true)
        case .ended, .cancelled, .failed:
            lockParentScroll(false)
        default:
            break
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
