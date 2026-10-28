import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Justified Text Component
/// A high-performance text view that renders justified text (căn đều 2 bên)
/// with full support for Markdown formatting, automatic intrinsic sizing,
/// dynamic line spacing, and dark luxury theme typography.
public struct JustifiedText: View {
    public let text: String
    public var font: Font
    public var textColor: Color
    public var lineSpacing: CGFloat
    public var fontSize: CGFloat
    public var fontWeight: Font.Weight
    
    public init(
        _ text: String,
        font: Font = AppTypography.caption,
        fontSize: CGFloat = 13,
        fontWeight: Font.Weight = .regular,
        textColor: Color = AppColors.primaryText,
        lineSpacing: CGFloat = 3.5
    ) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textColor = textColor
        self.lineSpacing = lineSpacing
    }
    
    public var body: some View {
        #if canImport(UIKit)
        JustifiedLabelRepresentable(
            text: text,
            fontSize: fontSize,
            weight: uiFontWeight(from: fontWeight),
            textColor: UIColor(textColor),
            lineSpacing: lineSpacing
        )
        #else
        Text(LocalizedStringKey(text))
            .font(font)
            .foregroundColor(textColor)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
        #endif
    }
    
    #if canImport(UIKit)
    private func uiFontWeight(from weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
    #endif
}

#if canImport(UIKit)
// MARK: - UIKit Justified Label Representable
struct JustifiedLabelRepresentable: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let weight: UIFont.Weight
    let textColor: UIColor
    let lineSpacing: CGFloat
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .justified
        label.isUserInteractionEnabled = false
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = createAttributedString()
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }
        uiView.attributedText = createAttributedString()
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
    
    private func createAttributedString() -> NSAttributedString {
        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.hyphenationFactor = 0.4
        
        let parsingOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        
        if let attrStr = try? AttributedString(markdown: text, options: parsingOptions) {
            let nsAttr = NSMutableAttributedString(attrStr)
            let fullRange = NSRange(location: 0, length: nsAttr.length)
            
            nsAttr.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                if let f = value as? UIFont {
                    let descriptor = f.fontDescriptor.withSize(fontSize)
                    nsAttr.addAttribute(.font, value: UIFont(descriptor: descriptor, size: fontSize), range: range)
                } else {
                    nsAttr.addAttribute(.font, value: baseFont, range: range)
                }
            }
            
            nsAttr.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if value == nil {
                    nsAttr.addAttribute(.foregroundColor, value: textColor, range: range)
                }
            }
            
            nsAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            return nsAttr
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }
}
#endif
