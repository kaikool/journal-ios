import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// High-performance, zero-latency Apple Native Haptic engine.
/// Reuses pre-prepared feedback generators to maximize 120Hz ProMotion responsiveness.
@MainActor
public enum NativeHaptics {
    #if canImport(UIKit)
    private static let lightGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        return gen
    }()
    
    private static let mediumGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        return gen
    }()
    
    private static let heavyGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        return gen
    }()
    
    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        return gen
    }()
    
    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        return gen
    }()
    #endif
    
    /// Triggered on tab switches, time range changes, and segmented controls.
    public static func selection() {
        #if canImport(UIKit)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }
    
    /// Triggered on button taps, list row taps, and light card swipes.
    public static func lightImpact() {
        #if canImport(UIKit)
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }
    
    /// Triggered on swipe action threshold reached, delete confirmation, and modal presentation.
    public static func mediumImpact() {
        #if canImport(UIKit)
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }
    
    /// Triggered on critical warnings or danger zone actions.
    public static func heavyImpact() {
        #if canImport(UIKit)
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
        #endif
    }
    
    /// Triggered on successful actions (e.g. sync completed, trade imported, note saved).
    public static func success() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }
    
    /// Triggered on validation errors or warnings.
    public static func warning() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
        #endif
    }
    
    /// Triggered on failed operations or network errors.
    public static func error() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
        #endif
    }
}
