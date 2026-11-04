import SwiftUI

// MARK: - Unified TradingView Viewport State & Math Engine
public struct ChartViewportMetrics {
    public let plotWidth: CGFloat
    public let plotHeight: CGFloat
    public let stepX: CGFloat
    public let candleWidth: CGFloat
    public let clampedPan: CGFloat
    public let minP: Double
    public let maxP: Double
    public let span: Double
}

@MainActor
public struct ChartViewportState {
    public var hoveredBarIndex: Int? = nil
    public var hoveredTouchY: CGFloat? = nil
    public var zoomScale: CGFloat = 1.0
    public var panOffset: CGFloat = 0.0
    public var isManualPriceScale: Bool = false
    public var manualCenterPrice: Double = 0.0
    public var manualPriceSpan: Double = 0.0
    public var currentPlotWidth: CGFloat = 320
    public var currentPlotHeight: CGFloat = 220
    public var didInitializeViewport: Bool = false

    public init() {}

    public func computeMetrics(
        bars: [MarketBar],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        defaultVisibleBars: Int
    ) -> ChartViewportMetrics {
        let pw = max(10, plotWidth)
        let ph = max(10, plotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = pw / CGFloat(max(1.0, slotCount))
        let candleWidth = max(2.0, min(22.0, stepX * 0.72))

        let maxRightSpace = max(stepX * 6.0, pw * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, pw - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))

        let autoBounds = Self.computeAutoPriceBounds(bars: bars, stepX: stepX, clampedPan: clampedPan, plotWidth: pw)
        let minP: Double
        let maxP: Double
        if isManualPriceScale && manualPriceSpan > 0 {
            minP = manualCenterPrice - (manualPriceSpan / 2.0)
            maxP = manualCenterPrice + (manualPriceSpan / 2.0)
        } else {
            minP = autoBounds.minP
            maxP = autoBounds.maxP
        }
        let span = max(0.00001, maxP - minP)

        return ChartViewportMetrics(
            plotWidth: pw,
            plotHeight: ph,
            stepX: stepX,
            candleWidth: candleWidth,
            clampedPan: clampedPan,
            minP: minP,
            maxP: maxP,
            span: span
        )
    }

    public static func computeAutoPriceBounds(
        bars: [MarketBar],
        stepX: CGFloat,
        clampedPan: CGFloat,
        plotWidth: CGFloat
    ) -> (minP: Double, maxP: Double) {
        guard !bars.isEmpty, stepX > 0 else { return (1.0, 2.0) }
        let leftX = -clampedPan
        let rightX = leftX + plotWidth
        let startIdx = max(0, min(bars.count - 1, Int(floor(leftX / stepX))))
        let endIdx = max(startIdx, min(bars.count - 1, Int(ceil(rightX / stepX))))

        let slice = bars[startIdx...endIdx]
        let lows = slice.map { ($0.low as NSDecimalNumber).doubleValue }
        let highs = slice.map { ($0.high as NSDecimalNumber).doubleValue }
        let minVal = lows.min() ?? 1.0
        let maxVal = highs.max() ?? 2.0
        let rawSpan = max(0.0001, maxVal - minVal)
        let pad = rawSpan * 0.08
        return (minP: minVal - pad, maxP: maxVal + pad)
    }

    public mutating func resetViewport(barsCount: Int, plotWidth: CGFloat, defaultVisibleBars: Int) {
        let pw = max(10, plotWidth)
        zoomScale = 1.0
        isManualPriceScale = false
        manualCenterPrice = 0
        manualPriceSpan = 0
        hoveredBarIndex = nil
        hoveredTouchY = nil
        let stepX = pw / CGFloat(max(1, defaultVisibleBars))
        let defaultRightMargin = stepX * 5.0
        let totalW = CGFloat(barsCount) * stepX + defaultRightMargin
        panOffset = min(0, pw - totalW)
    }

    public mutating func resetPriceScaleToAuto() {
        isManualPriceScale = false
        manualCenterPrice = 0
        manualPriceSpan = 0
    }

    public mutating func ensureManualPriceScaleInitialized(bars: [MarketBar], stepX: CGFloat, plotWidth: CGFloat) {
        guard !isManualPriceScale || manualPriceSpan <= 0 else { return }
        let maxRightSpace = max(stepX * 6.0, plotWidth * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, plotWidth - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))
        let auto = Self.computeAutoPriceBounds(bars: bars, stepX: stepX, clampedPan: clampedPan, plotWidth: plotWidth)
        manualCenterPrice = (auto.minP + auto.maxP) / 2.0
        manualPriceSpan = max(0.00001, auto.maxP - auto.minP)
        isManualPriceScale = true
    }

    public mutating func handleCanvasPan(
        bars: [MarketBar],
        defaultVisibleBars: Int,
        dx: CGFloat,
        dy: CGFloat,
        totalDx: CGFloat,
        totalDy: CGFloat
    ) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        let maxRightSpace = max(stepX * 6.0, plotW * 0.45)
        let totalW = CGFloat(bars.count) * stepX + maxRightSpace
        let minOffset = min(0, plotW - totalW)
        let maxOffset = stepX * 2.0
        panOffset = min(maxOffset, max(minOffset, panOffset + dx))

        if !isManualPriceScale && abs(totalDy) > 10 && abs(totalDy) > abs(totalDx) * 1.1 {
            ensureManualPriceScaleInitialized(bars: bars, stepX: stepX, plotWidth: plotW)
        }
        if isManualPriceScale && manualPriceSpan > 0 {
            let priceShift = (Double(dy) / Double(plotH)) * manualPriceSpan
            manualCenterPrice += priceShift
        }
    }

    public mutating func handlePriceAxisZoom(bars: [MarketBar], defaultVisibleBars: Int, dy: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        ensureManualPriceScaleInitialized(bars: bars, stepX: stepX, plotWidth: plotW)
        let scaleChange = max(0.85, min(1.18, 1.0 + Double(dy / max(80, plotH)) * 1.8))
        manualPriceSpan = max(0.00001, manualPriceSpan * scaleChange)
    }

    public mutating func handleTimeAxisZoom(barsCount: Int, defaultVisibleBars: Int, dx: CGFloat) {
        guard barsCount > 0 else { return }
        let plotW = max(10, currentPlotWidth)
        let scaleDelta = max(0.85, min(1.18, 1.0 + (dx / max(90, plotW)) * 1.8))
        let oldSlotCount = max(6.0, Double(defaultVisibleBars) / Double(zoomScale))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let anchorX = max(plotW * 0.5, min(plotW, plotW - oldStepX * 5.0))
        applyHorizontalZoom(barsCount: barsCount, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, anchorX: anchorX)
    }

    public mutating func handlePinchZoom(barsCount: Int, defaultVisibleBars: Int, scaleDelta: CGFloat, focalX: CGFloat) {
        guard barsCount > 0 else { return }
        let plotW = max(10, currentPlotWidth)
        let anchorX = max(0, min(plotW, focalX))
        applyHorizontalZoom(barsCount: barsCount, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, anchorX: anchorX)
    }

    public mutating func applyHorizontalZoom(barsCount: Int, defaultVisibleBars: Int, scaleDelta: CGFloat, anchorX: CGFloat) {
        let plotW = max(10, currentPlotWidth)
        let oldZoom = zoomScale
        let newZoom = max(0.25, min(6.0, oldZoom * scaleDelta))
        guard abs(newZoom - oldZoom) > 0.0001 else { return }

        let oldSlotCount = max(6.0, Double(defaultVisibleBars) / Double(oldZoom))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let barPosAtAnchor = (anchorX - panOffset) / oldStepX

        zoomScale = newZoom

        let newSlotCount = max(6.0, Double(defaultVisibleBars) / Double(newZoom))
        let newStepX = plotW / CGFloat(max(1.0, newSlotCount))
        let maxRightSpace = max(newStepX * 6.0, plotW * 0.45)
        let newTotalW = CGFloat(barsCount) * newStepX + maxRightSpace
        let newMinOffset = min(0, plotW - newTotalW)
        let newMaxOffset = newStepX * 2.0

        let rawNewPan = anchorX - (barPosAtAnchor * newStepX)
        panOffset = min(newMaxOffset, max(newMinOffset, rawNewPan))
    }

    public mutating func updateHoveredBar(
        at x: CGFloat,
        barsCount: Int,
        defaultVisibleBars: Int,
        stepX: CGFloat? = nil
    ) {
        guard barsCount > 0, currentPlotWidth > 0 else { return }
        let stX: CGFloat = {
            if let s = stepX, s > 0 { return s }
            let effectiveZoom = max(0.25, min(6.0, zoomScale))
            let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
            return currentPlotWidth / CGFloat(max(1.0, slotCount))
        }()
        let adjustedX = x - panOffset
        let index = max(0, min(barsCount - 1, Int(adjustedX / stX)))
        if hoveredBarIndex != index {
            hoveredBarIndex = index
            NativeHaptics.selection()
        }
    }
}
