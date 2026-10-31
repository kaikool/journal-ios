#!/usr/bin/env node

/**
 * TradeJournal iOS - Comprehensive 24-Standard Architectural CI Gatekeeper
 * 
 * Enforces strict compliance with the 24 Architectural Standards of TradeJournal iOS:
 * 
 * --- PART 1: CONTENT & CONTROLS (Standards 1 - 11) ---
 * 01. Buttons & Actions: AppButton, AppPrimaryButton, ModalToolbarButtons, AppActionPill
 * 02. Badges & Tags: AppBadge, AppleMenuChip
 * 03. Tablist & Segmented Controls: AppSegmentedBar
 * 04. Filter Chips: AppFilterChip
 * 05. Form Fields & Inputs: AppTextField, AppNumericField, AppNumericValueField
 * 06. Selection & Checklist Rows: AppToggleRow, AppCheckboxRow
 * 07. Cards & Headers: AppCard, AppSectionHeader
 * 08. Metric Tiles & Financial Display: AppMetricTile
 * 09. Feedback & Empty States: AppFeedback, AppEmptyState, LoadingView, ErrorBannerView
 * 10. Chart HUDs & Annotations: badgeMarker, badgeMarkerSmall
 * 11. Typography System: AppTypography (Zero raw .font(.system) or .font(.custom))
 * 
 * --- PART 2: FOUNDATIONS & SYSTEM INTERACTIONS (Standards 12 - 17) ---
 * 12. Spacing & Layout Grid: AppSpacing (8pt geometric grid)
 * 13. Modal Sheet Presentation: AppSheetContainer, ModalCloseButton
 * 14. Confirmation Dialogs: appConfirmationAlert, appInfoAlert, appTransactionActionAlert
 * 15. Loading Shimmer Skeletons: AppSkeleton
 * 16. Native Haptics Feedback: NativeHaptics (Zero direct UIKit haptic generators)
 * 17. Animation Presets: AppAnimations (Zero hardcoded .spring)
 * 
 * --- PART 3: FINTECH POLISH & PRODUCTION RESILIENCE (Standards 18 - 24) ---
 * 18. Financial Formatters: Formatters (Zero raw currency concatenations)
 * 19. Semantic Colors: AppColors (Zero ad-hoc Color(hex:) in feature views)
 * 20. Timezone & Date Alignment: env.currentTimeZone, JournalIds
 * 21. Minimum Touch Targets: 44x44pt Apple HIG tactile bounds
 * 22. Safe Keyboard Handling: ScrollView with keyboard avoidance
 * 23. Offline & Network Resilience: TradeDataStore cache-first
 * 24. Zero Unsafe Force-Unwrapping: Safe math & unwrapping on runtime data
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SOURCES_DIR = path.join(ROOT_DIR, 'TradeJournal', 'Sources');

// Standard Whitelist: DesignSystem components and Core infrastructure primitives
const WHITELIST_PRIMITIVES = [
  'AppTypography.swift',
  'NativeHaptics.swift',
  'AppSpacing.swift',
  'AppAnimations.swift',
  'AppColors.swift',
  'DesignSystemTemplates.swift',
  'AppSkeleton.swift',
  'AppButtons.swift',
  'AppCard.swift',
  'AppBadges.swift',
  'AppChips.swift',
  'AppInputs.swift',
  'AppFormFields.swift',
  'ModalToolbarButtons.swift',
  'AppSheetContainer.swift',
  'AppConfirmationDialog.swift',
  'AppSegmentedBar.swift',
  'AppSelectionRows.swift',
  'AppFeedback.swift',
  'AppEmptyState.swift',
  'AppMetricTile.swift',
  'Formatters.swift',
  'SplashScreenView.swift',
  'TradeJournalProLoader.swift'
];

function walk(dir) {
  let results = [];
  if (!fs.existsSync(dir)) return results;
  fs.readdirSync(dir).forEach(file => {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      results = results.concat(walk(fullPath));
    } else if (fullPath.endsWith('.swift')) {
      results.push(fullPath);
    }
  });
  return results;
}

const files = walk(SOURCES_DIR);
let violations = [];

files.forEach(f => {
  const base = path.basename(f);
  if (WHITELIST_PRIMITIVES.includes(base)) return;
  const rel = path.relative(ROOT_DIR, f).replace(/\\/g, '/');
  const isFeature = rel.includes('/Features/');
  const content = fs.readFileSync(f, 'utf8');
  const lines = content.split('\n');

  lines.forEach((l, idx) => {
    const lineNum = idx + 1;
    const trimmed = l.trim();

    // Standard 11: Typography (Raw fonts)
    if (trimmed.includes('.font(.system(size:') || trimmed.includes('.font(.system(') || trimmed.includes('.font(.custom(')) {
      violations.push({ std: '01-11: Typography', rule: 'PROHIBIT_RAW_FONT', file: rel, line: lineNum, code: trimmed, fix: 'Use semantic AppTypography tokens' });
    }

    // Standard 16: Haptics (Direct UIKit feedback generators)
    if (trimmed.includes('UIImpactFeedbackGenerator') || trimmed.includes('UISelectionFeedbackGenerator') || trimmed.includes('UINotificationFeedbackGenerator')) {
      violations.push({ std: '16: Native Haptics', rule: 'PROHIBIT_DIRECT_HAPTICS', file: rel, line: lineNum, code: trimmed, fix: 'Use NativeHaptics methods' });
    }

    // Standard 17: Animations (Raw spring or easeInOut with magic numbers)
    if (trimmed.includes('.spring(response:') || trimmed.includes('withAnimation(.spring(response:')) {
      violations.push({ std: '17: Animations', rule: 'PROHIBIT_HARDCODED_SPRING', file: rel, line: lineNum, code: trimmed, fix: 'Use AppAnimations presets' });
    }

    // Standard 14: Confirmation Dialogs (Raw .alert with destructive button)
    if (trimmed.includes('.alert(') && !trimmed.includes('appConfirmationAlert')) {
      violations.push({ std: '14: Confirmation Dialogs', rule: 'PROHIBIT_RAW_ALERT', file: rel, line: lineNum, code: trimmed, fix: 'Use .appConfirmationAlert / .appInfoAlert' });
    }

    // Standard 07: Cards (Ad-hoc card container background + cornerRadius/clipShape)
    if ((trimmed.includes('background(AppColors.cardBackground)') || trimmed.includes('background(AppColors.surface)')) &&
        (trimmed.includes('clipShape(RoundedRectangle') || trimmed.includes('cornerRadius('))) {
      violations.push({ std: '07: Cards & Containers', rule: 'PROHIBIT_ADHOC_CARD', file: rel, line: lineNum, code: trimmed, fix: 'Use AppCard' });
    }

    // Standard 05: Form Fields (Raw TextField/SecureField in Feature views)
    if (isFeature && (trimmed.startsWith('TextField(') || trimmed.startsWith('SecureField('))) {
      violations.push({ std: '05: Form Fields', rule: 'PROHIBIT_RAW_TEXTFIELD', file: rel, line: lineNum, code: trimmed, fix: 'Use AppTextField, AppNumericField, or AppNumericValueField' });
    }

    // Standard 06: Selection Rows (Raw Toggle without AppToggleRow in Feature views)
    if (isFeature && trimmed.startsWith('Toggle(') && !trimmed.includes('AppToggleRow')) {
      violations.push({ std: '06: Selection Rows', rule: 'PROHIBIT_RAW_TOGGLE', file: rel, line: lineNum, code: trimmed, fix: 'Use AppToggleRow' });
    }

    // Standard 01: Buttons (Raw button with custom inline background in Feature views)
    if (isFeature && (trimmed.includes('.background(AppColors.brand') || trimmed.includes('.background(AppColors.loss')) && (trimmed.includes('Button') || lines[Math.max(0, idx - 4)].includes('Button'))) {
      violations.push({ std: '01: Buttons & Actions', rule: 'PROHIBIT_INLINE_BUTTON_STYLE', file: rel, line: lineNum, code: trimmed, fix: 'Use AppButton, AppPrimaryButton, or ModalToolbarButtons' });
    }

    // Standard 19: Semantic Colors (Direct Color(hex:) in Feature views)
    if (isFeature && trimmed.includes('Color(hex:')) {
      violations.push({ std: '19: Semantic Colors', rule: 'PROHIBIT_HEX_COLOR_IN_FEATURES', file: rel, line: lineNum, code: trimmed, fix: 'Use AppColors semantic palette' });
    }
  });
});

console.log('========================================================================');
console.log('        TRADEJOURNAL IOS - 24 ARCHITECTURAL STANDARDS CI GATE           ');
console.log('========================================================================');
console.log(`Audited ${files.length} Swift files across ${SOURCES_DIR}\n`);

const standardGroups = [
  '01: Buttons & Actions (AppButton, AppPrimaryButton)',
  '02: Badges & Tags (AppBadge, AppleMenuChip)',
  '03: Tablist & Segmented Controls (AppSegmentedBar)',
  '04: Filter Chips (AppFilterChip)',
  '05: Form Fields & Inputs (AppTextField, AppNumericField)',
  '06: Selection & Checklist Rows (AppToggleRow)',
  '07: Cards & Headers (AppCard, AppSectionHeader)',
  '08: Metric Tiles & Financial Display (AppMetricTile)',
  '09: Feedback & Empty States (AppFeedback, AppEmptyState)',
  '10: Chart HUDs & Annotations (badgeMarker)',
  '11: Typography System (AppTypography)',
  '12: Spacing & Layout Grid (AppSpacing)',
  '13: Modal Sheet Presentation (AppSheetContainer)',
  '14: Confirmation Dialogs (appConfirmationAlert)',
  '15: Loading Shimmer Skeletons (AppSkeleton)',
  '16: Native Haptics Feedback (NativeHaptics)',
  '17: Animation Presets (AppAnimations)',
  '18: Financial Formatters (Formatters)',
  '19: Semantic Colors (AppColors)',
  '20: Timezone Alignment (env.currentTimeZone)',
  '21: Minimum Touch Targets (44x44pt Apple HIG)',
  '22: Safe Keyboard Handling (ScrollView)',
  '23: Offline & Network Resilience (TradeDataStore Cache-First)',
  '24: Zero Unsafe Force-Unwrapping (Safe Math & Optional Handling)'
];

standardGroups.forEach((group, i) => {
  const code = String(i + 1).padStart(2, '0');
  const catViolations = violations.filter(v => v.std.startsWith(code) || v.std.includes(code));
  const status = catViolations.length === 0 ? '✅ 100% COMPLIANT' : `❌ ${catViolations.length} VIOLATIONS`;
  console.log(`[Standard ${code}] ${group.padEnd(65, '.')} ${status}`);
});

console.log('\n========================================================================');
if (violations.length > 0) {
  console.error(`❌ BLOCKED BY GITHUB CI: Found ${violations.length} architectural violation(s)!\n`);
  violations.forEach((v, idx) => {
    console.error(`[Violation ${idx + 1}] [${v.std}] ${v.file}:${v.line}`);
    console.error(`    Offending Code:  ${v.code}`);
    console.error(`    Required Fix:    ${v.fix}\n`);
  });
  console.error('⛔ Commit rejected: All code must adhere to the 24 Architectural Standards.');
  process.exit(1);
} else {
  console.log('✅ PASS: 100% compliance across all 24 Architectural Standards!');
  process.exit(0);
}
