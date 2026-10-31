import SwiftUI

/// Unified Animation Presets for TradeJournal iOS
public enum AppAnimations {
    /// 0.28s / 0.82: Quick responsive tactile spring (button presses, micro-toggles)
    public static let springQuick = Animation.spring(response: 0.28, dampingFraction: 0.82)
    
    /// 0.32s / 0.86: Standard UI element appearance and state transitions
    public static let springStandard = Animation.spring(response: 0.32, dampingFraction: 0.86)
    
    /// 0.35s / 0.72: Playful tactile spring for charts, progress bars, and badges
    public static let springBouncy = Animation.spring(response: 0.35, dampingFraction: 0.72)
    
    /// 0.38s / 0.88: Smooth fluid transition for sheet presentations and drawer slides
    public static let sheetSpring = Animation.spring(response: 0.38, dampingFraction: 0.88)
    
    /// 0.20s: Instant fade in / fade out for tooltips and overlays
    public static let easeInOutFast = Animation.easeInOut(duration: 0.20)
    
    /// 0.28s: Standard content fade transition
    public static let easeInOutStandard = Animation.easeInOut(duration: 0.28)
}
