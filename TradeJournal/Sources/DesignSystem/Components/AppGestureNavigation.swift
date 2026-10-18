import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Native Interactive Pop Gesture Enabler
#if canImport(UIKit)
/// Enables native iOS edge swipe-to-go-back gesture (interactivePopGestureRecognizer)
/// across any NavigationStack, even when custom toolbars or hidden navigation bars are used.
public struct NativeInteractivePopGestureEnabler: UIViewControllerRepresentable {
    public init() {}
    
    public func makeUIViewController(context: Context) -> PopGestureController {
        PopGestureController()
    }
    
    public func updateUIViewController(_ uiViewController: PopGestureController, context: Context) {
        uiViewController.setupGesture()
    }
    
    public class PopGestureController: UIViewController, UIGestureRecognizerDelegate {
        override public func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            setupGesture()
        }
        
        override public func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setupGesture()
        }
        
        func setupGesture() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let nav = self.navigationController else { return }
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = self
            }
        }
        
        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let nav = self.navigationController else { return false }
            return nav.viewControllers.count > 1
        }
        
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
    }
}
#endif

// MARK: - Interactive Edge Back Swipe Gesture Modifier
/// Provides an interactive left-edge swipe gesture that slides the view right
/// and triggers `onBack` when dragged past the threshold or flicked.
public struct InteractiveEdgeBackSwipeModifier: ViewModifier {
    let onBack: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }
    
    public func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            content
                .offset(x: isDragging ? max(0, dragOffset) : 0)
                #if canImport(UIKit)
                .background(NativeInteractivePopGestureEnabler().frame(width: 0, height: 0))
                #endif
            
            // 32pt active edge swipe sensor along the left screen bezel
            Color.clear
                .frame(width: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            if value.translation.width > 6 && abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                                isDragging = true
                                dragOffset = value.translation.width * 0.4
                            }
                        }
                        .onEnded { value in
                            guard isDragging else { return }
                            isDragging = false
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            if value.translation.width > 70 || velocity > 150 {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    dragOffset = 220
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    onBack()
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .ignoresSafeArea(.container, edges: .vertical)
        }
    }
}

// MARK: - Right Edge Swipe Trigger
/// Dedicated right edge swipe strip (28pt) along the right screen bezel.
/// Used to advance to the next primary tab or open the drawer from the right edge.
public struct RightEdgeSwipeTrigger: View {
    let onSwipe: () -> Void
    
    public init(onSwipe: @escaping () -> Void) {
        self.onSwipe = onSwipe
    }
    
    public var body: some View {
        Color.clear
            .frame(width: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -24 && abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                            onSwipe()
                        }
                    }
            )
            .ignoresSafeArea(.container, edges: .vertical)
    }
}

// MARK: - View Extensions
extension View {
    /// Enables interactive edge swipe-to-go-back for any view providing an `onBack` handler.
    public func interactiveEdgeBack(onBack: (() -> Void)?) -> some View {
        if let onBack = onBack {
            return AnyView(self.modifier(InteractiveEdgeBackSwipeModifier(onBack: onBack)))
        } else {
            return AnyView(self)
        }
    }
    
    /// Enables native interactive pop gesture recognizer in the enclosing UINavigationController.
    public func enableNativePopGesture() -> some View {
        #if canImport(UIKit)
        return self.background(NativeInteractivePopGestureEnabler().frame(width: 0, height: 0))
        #else
        return self
        #endif
    }
}
