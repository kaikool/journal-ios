import SwiftUI

// MARK: - Office-Style Rich Note Editor
// Standardized across all note input fields in the application.
// Mimics Windows Office formatting experience:
// - B: toggle bold on / off from current point
// - I: toggle italic on / off from current point
// - Numbered list: toggle 1. 2. 3. with smart Enter continuation
// - Bullet list: toggle • with smart Enter continuation
// - Smart Default Mode: Defaults to Preview if note has content; defaults to Edit if note is empty
// - Live Mode switch: Edit (Office tools) <-> Preview (exact AI Markdown typography)
public struct RichNoteEditor: View {
    @Binding public var text: String
    public var placeholder: String
    public var minHeight: CGFloat
    public var allowPreviewToggle: Bool
    public var initialPreviewMode: Bool?
    public var onSave: (() -> Void)?
    
    @State private var isPreviewMode: Bool
    @State private var hasUserManuallyToggled: Bool = false
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var isBoldActive: Bool = false
    @State private var isItalicActive: Bool = false
    @State private var isBulletActive: Bool = false
    @State private var isNumberedActive: Bool = false
    @State private var previousText: String = ""
    @State private var dynamicHeight: CGFloat
    
    public init(
        text: Binding<String>,
        placeholder: String = "Write thoughts or notes...",
        minHeight: CGFloat = 110,
        allowPreviewToggle: Bool = true,
        initialPreviewMode: Bool? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.allowPreviewToggle = allowPreviewToggle
        self.initialPreviewMode = initialPreviewMode
        self.onSave = onSave
        self._dynamicHeight = State(initialValue: minHeight)
        
        let hasContent = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let defaultMode = initialPreviewMode ?? hasContent
        self._isPreviewMode = State(initialValue: defaultMode)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Office Formatting Toolbar
            HStack(spacing: 6) {
                // Bold Button (B)
                formatButton(
                    label: "B",
                    isActive: isBoldActive,
                    font: .system(size: 13, weight: .black)
                ) {
                    toggleBold()
                }
                
                // Italic Button (I)
                formatButton(
                    label: "I",
                    isActive: isItalicActive,
                    font: .system(size: 13, weight: .bold, design: .serif),
                    isItalic: true
                ) {
                    toggleItalic()
                }
                
                // Numbered List Button (1. 2. 3.)
                formatIconButton(
                    systemName: "list.number",
                    isActive: isNumberedActive
                ) {
                    toggleNumbered()
                }
                
                // Bullet List Button (•)
                formatIconButton(
                    systemName: "list.bullet",
                    isActive: isBulletActive
                ) {
                    toggleBullet()
                }
                
                Spacer()
                
                if allowPreviewToggle {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        hasUserManuallyToggled = true
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isPreviewMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPreviewMode ? "pencil" : "eye")
                                .font(.system(size: 10, weight: .semibold))
                            Text(isPreviewMode ? "Edit" : "Preview")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isPreviewMode ? AppColors.brand : AppColors.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(isPreviewMode ? AppColors.brand.opacity(0.12) : AppColors.secondaryBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isPreviewMode ? AppColors.brand.opacity(0.3) : AppColors.border.opacity(0.5), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isPreviewMode ? 0.85 : 1.0)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppColors.secondaryBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.4), lineWidth: 0.6)
            )
            
            // Content Area: Either Edit TextEditor or Rendered Markdown Preview
            if isPreviewMode {
                previewContainer
            } else {
                editorContainer
            }
        }
        .onAppear {
            syncFormatStates()
            previousText = text
            if !hasUserManuallyToggled {
                let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if let initial = initialPreviewMode {
                    isPreviewMode = initial
                } else if hasContent {
                    isPreviewMode = true
                }
            }
        }
        .onChange(of: text) { _, newText in
            if !hasUserManuallyToggled && initialPreviewMode == nil {
                let hadContent = !previousText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasContentNow = !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hadContent && hasContentNow {
                    isPreviewMode = true
                }
            }
            previousText = newText
        }
    }
    
    @ViewBuilder
    private func formatButton(
        label: String,
        isActive: Bool,
        font: Font,
        isItalic: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            Text(label)
                .font(font)
                .italic(isItalic)
                .foregroundColor(isActive ? .white : AppColors.primaryText)
                .frame(width: 32, height: 28)
                .background(isActive ? AppColors.brand : AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? AppColors.brand : AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func formatIconButton(
        systemName: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isActive ? .white : AppColors.primaryText)
                .frame(width: 32, height: 28)
                .background(isActive ? AppColors.brand : AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? AppColors.brand : AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var editorContainer: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            
            #if canImport(UIKit)
            RichUITextView(
                text: $text,
                selectedRange: $selectedRange,
                isBoldActive: $isBoldActive,
                isItalicActive: $isItalicActive,
                isBulletActive: $isBulletActive,
                isNumberedActive: $isNumberedActive,
                minHeight: minHeight,
                dynamicHeight: $dynamicHeight,
                onSave: onSave
            )
            .frame(height: max(minHeight, dynamicHeight))
            #else
            TextEditor(text: $text)
                .font(AppTypography.inputText)
                .foregroundColor(AppColors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: minHeight)
                .onChange(of: text) { newValue in
                    let handled = NoteFormattingEngine.handleNewline(text: newValue, oldValue: previousText)
                    if handled != newValue {
                        text = handled
                    }
                    previousText = text
                    syncFormatStates()
                    onSave?()
                }
            #endif
        }
        .background(AppColors.secondaryBackground.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
        )
    }
    
    @ViewBuilder
    private var previewContainer: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                isPreviewMode = false
            }
        } label: {
            Group {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Text("No notes written yet. Tap to start writing...")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            .italic()
                        Spacer()
                    }
                    .padding(12)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                } else {
                    JournalNotesMarkdownView(text: text)
                        .padding(10)
                        .frame(minHeight: minHeight, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppColors.secondaryBackground.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.border.opacity(0.35), lineWidth: 0.6)
        )
    }
    
    private func toggleBold() {
        if isPreviewMode { isPreviewMode = false }
        let res = NoteFormattingEngine.toggleBold(in: text, range: selectedRange)
        text = res.text
        selectedRange = res.newRange
        isBoldActive = res.isActive
        previousText = text
        onSave?()
    }
    
    private func toggleItalic() {
        if isPreviewMode { isPreviewMode = false }
        let res = NoteFormattingEngine.toggleItalic(in: text, range: selectedRange)
        text = res.text
        selectedRange = res.newRange
        isItalicActive = res.isActive
        previousText = text
        onSave?()
    }
    
    private func toggleNumbered() {
        if isPreviewMode { isPreviewMode = false }
        let res = NoteFormattingEngine.toggleNumbered(in: text, range: selectedRange)
        text = res.text
        selectedRange = res.newRange
        isNumberedActive = res.isActive
        previousText = text
        onSave?()
    }
    
    private func toggleBullet() {
        if isPreviewMode { isPreviewMode = false }
        let res = NoteFormattingEngine.toggleBullet(in: text, range: selectedRange)
        text = res.text
        selectedRange = res.newRange
        isBulletActive = res.isActive
        previousText = text
        onSave?()
    }
    
    private func syncFormatStates() {
        let loc = selectedRange.location
        isBoldActive = NoteFormattingEngine.isBoldActive(in: text, at: loc)
        isItalicActive = NoteFormattingEngine.isItalicActive(in: text, at: loc)
        isBulletActive = NoteFormattingEngine.isBulletActive(in: text, at: loc)
        isNumberedActive = NoteFormattingEngine.isNumberedActive(in: text, at: loc)
    }
}

// MARK: - UIKit Real-Time Cursor & Selection TextView
#if canImport(UIKit)
import UIKit

public struct RichUITextView: UIViewRepresentable {
    @Binding public var text: String
    @Binding public var selectedRange: NSRange
    @Binding public var isBoldActive: Bool
    @Binding public var isItalicActive: Bool
    @Binding public var isBulletActive: Bool
    @Binding public var isNumberedActive: Bool
    public var minHeight: CGFloat
    @Binding public var dynamicHeight: CGFloat
    public var onSave: (() -> Void)?
    
    public init(
        text: Binding<String>,
        selectedRange: Binding<NSRange>,
        isBoldActive: Binding<Bool>,
        isItalicActive: Binding<Bool>,
        isBulletActive: Binding<Bool>,
        isNumberedActive: Binding<Bool>,
        minHeight: CGFloat,
        dynamicHeight: Binding<CGFloat>,
        onSave: (() -> Void)? = nil
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self._isBoldActive = isBoldActive
        self._isItalicActive = isItalicActive
        self._isBulletActive = isBulletActive
        self._isNumberedActive = isNumberedActive
        self.minHeight = minHeight
        self._dynamicHeight = dynamicHeight
        self.onSave = onSave
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = UIColor.label
        textView.backgroundColor = .clear
        textView.text = text
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        done.tintColor = UIColor(AppColors.brand)
        toolbar.items = [flex, done]
        textView.inputAccessoryView = toolbar
        
        context.coordinator.textView = textView
        
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: uiView)
        }
    }
    
    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichUITextView
        weak var textView: UITextView?
        
        init(_ parent: RichUITextView) {
            self.parent = parent
        }
        
        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }
        
        func recalculateHeight(for textView: UITextView) {
            let width = textView.bounds.width > 0 ? textView.bounds.width : (UIScreen.main.bounds.width - 48)
            let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let target = max(parent.minHeight, size.height)
            if abs(parent.dynamicHeight - target) > 1 {
                parent.dynamicHeight = target
            }
        }
        
        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            updateFormatStates(textView)
            recalculateHeight(for: textView)
            parent.onSave?()
        }
        
        public func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
            updateFormatStates(textView)
        }
        
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                let res = NoteFormattingEngine.handleReturnKey(in: textView.text, at: range.location)
                if res.handled {
                    textView.text = res.text
                    let newRange = NSRange(location: res.newLocation, length: 0)
                    textView.selectedRange = newRange
                    parent.text = res.text
                    parent.selectedRange = newRange
                    updateFormatStates(textView)
                    recalculateHeight(for: textView)
                    parent.onSave?()
                    return false
                }
            }
            return true
        }
        
        func updateFormatStates(_ textView: UITextView) {
            let loc = textView.selectedRange.location
            parent.isBoldActive = NoteFormattingEngine.isBoldActive(in: textView.text, at: loc)
            parent.isItalicActive = NoteFormattingEngine.isItalicActive(in: textView.text, at: loc)
            parent.isBulletActive = NoteFormattingEngine.isBulletActive(in: textView.text, at: loc)
            parent.isNumberedActive = NoteFormattingEngine.isNumberedActive(in: textView.text, at: loc)
        }
    }
}
#endif
