#!/usr/bin/env node

/**
 * ========================================================================
 * TRADEJOURNAL IOS - 26 ARCHITECTURAL STANDARDS CI GATEKEEPER
 * ========================================================================
 * 
 * Strict Single Source of Truth & Zero Inline Code Governance.
 * Audits all Swift source files against the 26 Architectural Standards.
 * Ordered sequentially from Standard 01 to Standard 26:
 * 
 * --- PART 1: CONTENT & CONTROLS (Standards 01 - 11) ---
 * Standard 01: Buttons & Actions (AppButton, AppPrimaryButton, ModalToolbarButtons)
 * Standard 02: Badges & Tags (AppBadge, AppleMenuChip)
 * Standard 03: Tablist & Segmented Controls (AppSegmentedBar, AppBinarySegmentedToggle)
 * Standard 04: Filter Chips (AppFilterChip)
 * Standard 05: Form Fields & Inputs (AppTextField, AppNumericField, AppDecimalField)
 * Standard 06: Selection & Checklist Rows (AppToggleRow, AppCheckboxRow)
 * Standard 07: Cards & Headers (AppCard, AppSectionHeader, appCardStyle, appSubCardStyle)
 * Standard 08: Metric Tiles & Financial Display (AppMetricTile)
 * Standard 09: Feedback & Empty States (AppEmptyState, LoadingView, TradeJournalProLoader)
 * Standard 10: Chart HUDs & Annotations (badgeMarker, badgeMarkerSmall)
 * Standard 11: Typography System (AppTypography - Zero raw fonts)
 * 
 * --- PART 2: FOUNDATIONS & SYSTEM INTERACTIONS (Standards 12 - 17) ---
 * Standard 12: Spacing & Layout Grid (AppSpacing geometric scale)
 * Standard 13: Modal Sheet Presentation (AppSheetContainer, ModalCloseButton)
 * Standard 14: Confirmation Dialogs (appConfirmationAlert, appInfoAlert)
 * Standard 15: Loading Shimmer Skeletons (AppSkeleton)
 * Standard 16: Native Haptics Feedback (NativeHaptics - Zero raw UIKit)
 * Standard 17: Animation Presets (AppAnimations - Zero hardcoded .spring)
 * 
 * --- PART 3: FINTECH POLISH & PRODUCTION RESILIENCE (Standards 18 - 26) ---
 * Standard 18: Financial Formatters (Formatters - Zero raw currency concat)
 * Standard 19: Semantic Color Hierarchy (AppColors - Zero ad-hoc Color(hex:))
 * Standard 20: Timezone & Date Alignment (env.currentTimeZone, JournalIds)
 * Standard 21: Minimum Touch Target Bounds (Apple HIG 44x44pt tactile bounds)
 * Standard 22: Safe Keyboard Handling (ScrollView embed for form safety)
 * Standard 23: Offline-First & Network Resilience (TradeDataStore cache-first)
 * Standard 24: Zero Unsafe Force-Unwrapping & Safe Math (Safe math & optionals)
 * Standard 25: Push Notifications & Alert Dispatching (AppNotificationManager - Zero raw UNNotification in views)
 * Standard 26: Source Size Limits (no Swift file over MAX_FILE_LINES lines)
 * Standard 27: Unified Alerting & Notification Architecture (AppNotificationCoordinator, Zero Emoji in Alerts)
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SOURCES_DIR = path.join(ROOT_DIR, 'TradeJournal', 'Sources');

// Whitelisted Design System Primitives & Launch Infrastructure
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
  'TradeJournalProLoader.swift',
  'AppNotificationManager.swift'
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
  const isCompositeDS = rel.includes('AttachmentsSectionView.swift') ||
                        rel.includes('FullScreenChartLightboxView.swift') ||
                        rel.includes('GlobalSyncBannerView.swift');
  const isFeature = rel.includes('/Features/') || isCompositeDS;
  const content = fs.readFileSync(f, 'utf8');
  const lines = content.split('\n');

  let inMenuOrContextMenu = 0;
  lines.forEach((l, idx) => {
    const lineNum = idx + 1;
    const trimmed = l.trim();

    // Track whether we are inside native iOS Menu or contextMenu
    if (trimmed.includes('Menu {') || trimmed.includes('Menu(') || trimmed.includes('.contextMenu {') || trimmed.includes('AppleMenuChip(')) {
      inMenuOrContextMenu = 8;
    }
    if (inMenuOrContextMenu > 0 && trimmed.startsWith('}')) {
      inMenuOrContextMenu--;
    }

    // =========================================================================
    // PART 1: CONTENT & CONTROLS (STANDARDS 01 - 11)
    // =========================================================================

    // --- STANDARD 01: BUTTONS & ACTIONS ---
    // Prohibits raw button styling with inline backgrounds or custom frames in Feature views.
    if (isFeature && (trimmed.startsWith('Button(') || trimmed.startsWith('Button {') || /\bButton\s*(\(|\{)/.test(trimmed))) {
      const isAllowedDSButton = trimmed.includes('AppPrimaryButton') ||
                                trimmed.includes('AppSecondaryButton') ||
                                trimmed.includes('AppDestructiveButton') ||
                                trimmed.includes('AppActionPill') ||
                                trimmed.includes('Modal');
      if (!isAllowedDSButton && inMenuOrContextMenu <= 0) {
        violations.push({
          std: 'Standard 01: Buttons & Actions',
          rule: 'PROHIBIT_RAW_BUTTON',
          file: rel,
          line: lineNum,
          code: trimmed,
          fix: 'Use AppPrimaryButton, AppSecondaryButton, AppDestructiveButton, AppActionPill, or ModalCircleButton'
        });
      }
    }

    // --- STANDARD 02: BADGES & TAGS ---
    // Prohibits ad-hoc capsule badge wrappers in Feature views.
    if (isFeature && trimmed.includes('clipShape(Capsule())') &&
        !trimmed.includes('AppBadge') &&
        !trimmed.includes('AppFilterChip') &&
        !trimmed.includes('AppActionPill') &&
        !trimmed.includes('AppleMenuChip') &&
        !trimmed.includes('AppFloatingBar')) {
      for (let i = 1; i <= 3; i++) {
        if (idx - i >= 0 && lines[idx - i].includes('.background(')) {
          violations.push({
            std: 'Standard 02: Badges & Tags',
            rule: 'PROHIBIT_ADHOC_BADGE',
            file: rel,
            line: lineNum,
            code: trimmed,
            fix: 'Use AppBadge or AppleMenuChip'
          });
          break;
        }
      }
    }

    // --- STANDARD 03: TABLIST & SEGMENTED CONTROLS ---
    // Prohibits raw segmented picker loops or ad-hoc button groups in Feature views.
    if (isFeature && trimmed.includes('.pickerStyle(.segmented)') && !trimmed.includes('AppSegmentedBar')) {
      violations.push({
        std: 'Standard 03: Tablist & Segmented Controls',
        rule: 'PROHIBIT_RAW_SEGMENTED_PICKER',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppSegmentedBar for unified tactile tabs'
      });
    }

    // --- STANDARD 04: FILTER CHIPS ---
    // Prohibits unstandardized filter chip capsule toggles.
    if (isFeature && /\bFilterChip\s*\(/.test(trimmed)) {
      violations.push({
        std: 'Standard 04: Filter Chips',
        rule: 'PROHIBIT_RAW_FILTER_CHIP',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppFilterChip'
      });
    }

    // --- STANDARD 05: FORM FIELDS & INPUTS ---
    // Prohibits raw TextField / SecureField / Picker in Feature views without AppTextField / AppNumericField / AppCompactDropdown.
    if (isFeature && (trimmed.startsWith('TextField(') || trimmed.startsWith('SecureField('))) {
      violations.push({
        std: 'Standard 05: Form Fields & Inputs',
        rule: 'PROHIBIT_RAW_TEXTFIELD',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppTextField, AppNumericField, AppNumericValueField, or AppDecimalField'
      });
    }
    if (isFeature && /\bPicker\s*\(/.test(trimmed) && !trimmed.includes('AppSegmentedBar')) {
      violations.push({
        std: 'Standard 05: Form Fields & Inputs',
        rule: 'PROHIBIT_RAW_PICKER',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppDropdownField, AppCompactDropdown, or AppSegmentedBar'
      });
    }
    // Prohibits wrapping an AppTextField or AppFormField inside an outer .appSubCardStyle or .appCardStyle container
    if (isFeature && (trimmed.includes('AppTextField(') || trimmed.includes('AppFormField(') || trimmed.includes('AppNumericField(') || trimmed.includes('AppDropdownField('))) {
      for (let i = 1; i <= 8; i++) {
        if (idx + i < lines.length) {
          const next = lines[idx + i].trim();
          if (next.includes('.appSubCardStyle') || next.includes('.appCardStyle')) {
            violations.push({
              std: 'Standard 05: Form Fields & Inputs',
              rule: 'PROHIBIT_NESTED_INPUT_CARD',
              file: rel,
              line: lineNum,
              code: trimmed + ' -> ' + next,
              fix: 'Do not wrap input fields in an outer card. Inputs provide their own clean container.'
            });
            break;
          }
        }
      }
    }

    // Prohibits custom ad-hoc Menu labels with appCardStyle or background (e.g. ad-hoc dropdowns)
    if (isFeature && (trimmed.includes('Menu {') || trimmed.includes('Menu('))) {
      for (let k = 1; k <= 35; k++) {
        if (idx + k < lines.length) {
          const next = lines[idx + k].trim();
          if (next.includes('} label:') && lines.slice(idx + k, idx + k + 12).some(x => x.includes('.appCardStyle'))) {
            violations.push({
              std: 'Standard 05: Form Fields & Inputs',
              rule: 'PROHIBIT_ADHOC_MENU_LABEL',
              file: rel,
              line: lineNum,
              code: trimmed + ' -> custom card label',
              fix: 'Use AppleMenuChip or AppCompactDropdown instead of custom Menu card labels'
            });
            break;
          }
        }
      }
    }

    // --- STANDARD 06: SELECTION & CHECKLIST ROWS ---
    // Prohibits raw Toggle in Feature views without AppToggleRow.
    if (isFeature && trimmed.startsWith('Toggle(') && !trimmed.includes('AppToggleRow')) {
      violations.push({
        std: 'Standard 06: Selection & Checklist Rows',
        rule: 'PROHIBIT_RAW_TOGGLE',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppToggleRow or AppCheckboxRow'
      });
    }

    // --- STANDARD 07: CARDS & HEADERS ---
    // Prohibits manual card background + rounded rectangle container styling in Feature views.
    if (isFeature && trimmed.includes('.background(')) {
      for (let i = 1; i <= 4; i++) {
        if (idx + i < lines.length) {
          const next = lines[idx + i].trim();
          if ((next.includes('clipShape(RoundedRectangle') || next.includes('cornerRadius(')) &&
              !next.includes('appCardStyle') &&
              !next.includes('appSubCardStyle') &&
              !next.includes('AppCard') &&
              !next.includes('AppChatBubble') &&
              !next.includes('AppBinarySegmentedToggle')) {
            violations.push({
              std: 'Standard 07: Cards & Headers',
              rule: 'PROHIBIT_ADHOC_CARD',
              file: rel,
              line: lineNum,
              code: trimmed + ' -> ' + next,
              fix: 'Use AppCard, .appCardStyle(), or .appSubCardStyle() from DesignSystem'
            });
            break;
          }
        }
      }
    }

    // --- STANDARD 08: METRIC TILES & FINANCIAL DISPLAY ---
    // Prohibits manual KPI block styling in Feature views.
    if (isFeature && /\bMetricTile\s*\(/.test(trimmed)) {
      violations.push({
        std: 'Standard 08: Metric Tiles & Financial Display',
        rule: 'PROHIBIT_RAW_METRIC_TILE',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppMetricTile'
      });
    }

    // --- STANDARD 09: FEEDBACK & EMPTY STATES ---
    // Prohibits raw ProgressView or custom EmptyState in Feature views.
    if (isFeature && /\bProgressView\b/.test(trimmed) && !trimmed.includes('ProgressView(value:')) {
      violations.push({
        std: 'Standard 09: Feedback & Empty States',
        rule: 'PROHIBIT_RAW_PROGRESS_VIEW',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use LoadingView(...) or TradeJournalProLoader from DesignSystem'
      });
    }
    if (isFeature && (/\bEmptyStateView\b/.test(trimmed) || /\bEmptyState\s*\(/.test(trimmed))) {
      violations.push({
        std: 'Standard 09: Feedback & Empty States',
        rule: 'PROHIBIT_RAW_EMPTY_STATE',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppEmptyState, LoadingView, or ErrorBannerView'
      });
    }

    // --- STANDARD 10: CHART HUDS & ANNOTATIONS ---
    // Prohibits ad-hoc font tokens or custom badges inside chart annotations.
    if (rel.includes('/Charts/') && trimmed.includes('.font(.caption2)') && !trimmed.includes('badgeMarker')) {
      violations.push({
        std: 'Standard 10: Chart HUDs & Annotations',
        rule: 'PROHIBIT_RAW_CHART_HUD_FONT',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppTypography.badgeMarker or AppTypography.badgeMarkerSmall'
      });
    }

    // --- STANDARD 11: TYPOGRAPHY SYSTEM ---
    // Prohibits raw .font(.system) or .font(.custom) across all source files.
    if (trimmed.includes('.font(.system(size:') || trimmed.includes('.font(.system(') || trimmed.includes('.font(.custom(')) {
      violations.push({
        std: 'Standard 11: Typography System',
        rule: 'PROHIBIT_RAW_FONT',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use semantic AppTypography tokens (displayHero, metricLarge, cardHeader, rowTitle, etc.)'
      });
    }

    // =========================================================================
    // PART 2: FOUNDATIONS & SYSTEM INTERACTIONS (STANDARDS 12 - 17)
    // =========================================================================

    // --- STANDARD 12: SPACING & LAYOUT GRID ---
    // Prohibits random magic numbers in padding.
    if (/\.padding\(\s*(11|13|17|19|23|29)\s*\)/.test(trimmed)) {
      violations.push({
        std: 'Standard 12: Spacing & Layout Grid',
        rule: 'PROHIBIT_MAGIC_SPACING',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppSpacing scale (.micro, .small, .standard, .cardPadding, .pageMargin, .sectionGutter)'
      });
    }

    // --- STANDARD 13: MODAL SHEET PRESENTATION ---
    // Prohibits manual toolbar dismiss button constructions in modal sheets.
    if (isFeature && trimmed.includes('.sheet(') && trimmed.includes('NavigationView')) {
      violations.push({
        std: 'Standard 13: Modal Sheet Presentation',
        rule: 'PROHIBIT_LEGACY_SHEET_NAV',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppSheetContainer with ModalCloseButton'
      });
    }

    // --- STANDARD 14: CONFIRMATION DIALOGS ---
    // Prohibits raw .alert in Feature views without appConfirmationAlert wrapper.
    if (trimmed.includes('.alert(') && !trimmed.includes('appConfirmationAlert') && !trimmed.includes('appInfoAlert') && !trimmed.includes('appTransactionActionAlert')) {
      violations.push({
        std: 'Standard 14: Confirmation Dialogs',
        rule: 'PROHIBIT_RAW_ALERT',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use .appConfirmationAlert, .appInfoAlert, or .appTransactionActionAlert'
      });
    }

    // --- STANDARD 15: LOADING SHIMMER SKELETONS ---
    // Prohibits ad-hoc Skeleton wrappers.
    if (isFeature && /\bSkeleton\s*\(/.test(trimmed)) {
      violations.push({
        std: 'Standard 15: Loading Shimmer Skeletons',
        rule: 'PROHIBIT_RAW_SKELETON',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppSkeleton component'
      });
    }

    // --- STANDARD 16: NATIVE HAPTICS FEEDBACK ---
    // Prohibits direct UIKit feedback generators or unqualified .lightImpact() calls.
    if (trimmed.includes('UIImpactFeedbackGenerator') ||
        trimmed.includes('UISelectionFeedbackGenerator') ||
        trimmed.includes('UINotificationFeedbackGenerator') ||
        /(?<!NativeHaptics)\.(lightImpact|mediumImpact|heavyImpact|selection)\(\)/.test(trimmed)) {
      violations.push({
        std: 'Standard 16: Native Haptics Feedback',
        rule: 'PROHIBIT_DIRECT_HAPTICS',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use NativeHaptics.lightImpact(), NativeHaptics.mediumImpact(), or NativeHaptics.selection()'
      });
    }
    // Prohibits interactive tap gestures without native haptic feedback
    if (isFeature && trimmed.startsWith('.onTapGesture {')) {
      let hasHaptics = false;
      for (let k = 1; k <= 4; k++) {
        if (idx + k < lines.length && lines[idx + k].includes('NativeHaptics.')) {
          hasHaptics = true;
          break;
        }
      }
      if (!hasHaptics) {
        violations.push({
          std: 'Standard 16: Native Haptics Feedback',
          rule: 'PROHIBIT_TAP_WITHOUT_HAPTICS',
          file: rel,
          line: lineNum,
          code: trimmed,
          fix: 'All interactive taps in Feature views must trigger NativeHaptics.lightImpact()'
        });
      }
    }

    // --- STANDARD 17: ANIMATION PRESETS ---
    // Prohibits hardcoded .spring or withAnimation with raw spring configs.
    if (trimmed.includes('.spring(response:') || trimmed.includes('withAnimation(.spring(response:')) {
      violations.push({
        std: 'Standard 17: Animation Presets',
        rule: 'PROHIBIT_HARDCODED_SPRING',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppAnimations presets (springQuick, springStandard, sheetSpring, easeInOutFast)'
      });
    }

    // =========================================================================
    // PART 3: FINTECH POLISH & PRODUCTION RESILIENCE (STANDARDS 18 - 24)
    // =========================================================================

    // --- STANDARD 18: FINANCIAL FORMATTERS ---
    // Prohibits raw string concatenation or manual formatting for currency or pips.
    const isManualFinancial = isFeature && (
      trimmed.includes('"$(\\(') ||
      trimmed.includes('"$+\\(') ||
      trimmed.includes('"$-\\(') ||
      trimmed.includes('"+$\\(') ||
      trimmed.includes('"-$\\(') ||
      /String\(format:\s*"[+-]?\$/.test(trimmed) ||
      /String\(format:\s*".*pips/.test(trimmed)
    );
    if (isManualFinancial) {
      violations.push({
        std: 'Standard 18: Financial Formatters',
        rule: 'PROHIBIT_RAW_CURRENCY_INTERPOLATION',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use Formatters.formatCurrency(amount, currency: ...) or Formatters.pips(...)'
      });
    }

    // --- STANDARD 19: SEMANTIC COLOR HIERARCHY ---
    // Prohibits direct Color(hex:) or raw system colors in Feature views.
    if (isFeature && (trimmed.includes('Color(hex:') || /\bColor\.(blue|green|red|purple|orange|yellow)\b/.test(trimmed))) {
      violations.push({
        std: 'Standard 19: Semantic Color Hierarchy',
        rule: 'PROHIBIT_RAW_COLOR_IN_FEATURES',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppColors semantic palette (brand, profit, loss, warning, background, cardBackground, border)'
      });
    }

    // --- STANDARD 20: TIMEZONE & DATE ALIGNMENT ---
    // Prohibits raw unaligned Calendar.current in dayId operations.
    if (isFeature && trimmed.includes('Calendar.current') && trimmed.includes('dayId')) {
      violations.push({
        std: 'Standard 20: Timezone & Date Alignment',
        rule: 'PROHIBIT_RAW_CALENDAR_IN_DAYID',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppEnvironment.shared.currentTimeZone and JournalIds.dayId(for:timeZone:)'
      });
    }

    // --- STANDARD 21: MINIMUM TOUCH TARGET BOUNDS ---
    // Prohibits small touch targets under 44pt without tactile bounds expansion.
    if (isFeature && trimmed.includes('.frame(width: 24, height: 24)') && lines[Math.max(0, idx - 2)].includes('Button')) {
      violations.push({
        std: 'Standard 21: Minimum Touch Target Bounds',
        rule: 'PROHIBIT_SUB_44PT_TOUCH_TARGET',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Add .frame(minWidth: 44, minHeight: 44) or contentShape hit target expansion for Apple HIG'
      });
    }

    // --- STANDARD 22: SAFE KEYBOARD HANDLING ---
    // Prohibits bottom-anchored text fields without scroll container safety.
    if (isFeature && trimmed.includes('KeyboardAvoidanceModifier(')) {
      violations.push({
        std: 'Standard 22: Safe Keyboard Handling',
        rule: 'PROHIBIT_ADHOC_KEYBOARD_MODIFIER',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Embed editable form views inside ScrollView with automatic keyboard dismissal'
      });
    }

    // --- STANDARD 23: OFFLINE-FIRST & NETWORK RESILIENCE ---
    // Prohibits direct blocking synchronous URLSession calls in UI views.
    if (isFeature && trimmed.includes('URLSession.shared.data(from:') && !trimmed.includes('Task {')) {
      violations.push({
        std: 'Standard 23: Offline-First & Network Resilience',
        rule: 'PROHIBIT_BLOCKING_NETWORK_IN_VIEW',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use TradeDataStore cache-first methods and asynchronous background tasks'
      });
    }

    // --- STANDARD 24: ZERO UNSAFE FORCE-UNWRAPPING & SAFE MATH ---
    // Prohibits unsafe force unwraps on dynamic array indexing or API payloads in Features.
    if (isFeature && /(trades|accounts|rules)\[.*\]!/.test(trimmed)) {
      violations.push({
        std: 'Standard 24: Zero Unsafe Force-Unwrapping & Safe Math',
        rule: 'PROHIBIT_UNSAFE_FORCE_UNWRAP',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use safe optional binding (if let, guard let, or nil-coalescing ??)'
      });
    }

    // --- STANDARD 25: PUSH NOTIFICATIONS & ALERT DISPATCHING ---
    // Prohibits raw UNUserNotificationCenter calls in Feature views. All alerts must route via AppNotificationManager.
    if (isFeature && (trimmed.includes('UNUserNotificationCenter.current()') || trimmed.includes('UNMutableNotificationContent('))) {
      violations.push({
        std: 'Standard 25: Push Notifications & Alerts',
        rule: 'PROHIBIT_RAW_USER_NOTIFICATIONS_IN_VIEWS',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Use AppNotificationManager.shared for dispatching notifications and managing permissions'
      });
    }

    // --- STANDARD 27: UNIFIED ALERTING & NOTIFICATION ARCHITECTURE ---
    // Enforces institutional professional tone: Prohibits emoji / icons in alert titles or bodies.
    const EMOJI_IN_NOTIF_REGEX = /[\u{1F300}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}]/u;
    if ((trimmed.includes('dispatchNotification') || trimmed.includes('scheduleNotification')) && EMOJI_IN_NOTIF_REGEX.test(trimmed)) {
      violations.push({
        std: 'Standard 27: Unified Alerting & Notification Architecture',
        rule: 'PROHIBIT_EMOJI_IN_NOTIFICATION_STRINGS',
        file: rel,
        line: lineNum,
        code: trimmed,
        fix: 'Standard 27 strictly requires 100% Institutional Professional English with ZERO emojis or icons in notifications'
      });
    }
  });
});

// --- STANDARD 26: SOURCE SIZE LIMITS ---
// No Swift source file may exceed MAX_FILE_LINES lines. Split by responsibility into focused
// extension / model files instead. Functions longer than WARN_FUNCTION_LINES are reported as
// non-blocking warnings so they can be decomposed incrementally.
const MAX_FILE_LINES = 800;
const WARN_FUNCTION_LINES = 150;
const sizeWarnings = [];
files.forEach(f => {
  const rel = path.relative(ROOT_DIR, f).replace(/\\\\/g, '/');
  const srcLines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  let total = srcLines.length;
  while (total > 0 && srcLines[total - 1].trim() === '') total--;
  if (total > MAX_FILE_LINES) {
    violations.push({
      std: 'Standard 26: Source Size Limits',
      rule: 'PROHIBIT_OVERSIZED_SOURCE_FILE',
      file: rel,
      line: total,
      code: `File has ${total} lines (limit ${MAX_FILE_LINES})`,
      fix: 'Split the file into focused extension / model files grouped by responsibility'
    });
  }
  srcLines.forEach((line, idx) => {
    const m = line.match(/^(\s*).*\bfunc\s+\w+.*\{\s*$/);
    if (!m) return;
    const indent = m[1].length;
    for (let j = idx + 1; j < srcLines.length; j++) {
      const s = srcLines[j];
      if (s.trim().startsWith('}') && (s.length - s.trimStart().length) === indent) {
        if (j - idx + 1 > WARN_FUNCTION_LINES) {
          sizeWarnings.push({ file: rel, line: idx + 1, length: j - idx + 1 });
        }
        break;
      }
    }
  });
});
console.log('========================================================================');
console.log('        TRADEJOURNAL IOS - 27 ARCHITECTURAL STANDARDS CI GATE           ');
console.log('========================================================================');
console.log(`Audited ${files.length} Swift files across ${SOURCES_DIR}\n`);

const standardRegistry = [
  { code: '01', title: 'Buttons & Actions (AppButton, AppPrimaryButton)' },
  { code: '02', title: 'Badges & Tags (AppBadge, AppleMenuChip)' },
  { code: '03', title: 'Tablist & Segmented Controls (AppSegmentedBar, AppBinarySegmentedToggle)' },
  { code: '04', title: 'Filter Chips (AppFilterChip)' },
  { code: '05', title: 'Form Fields & Inputs (AppTextField, AppNumericField, AppDecimalField)' },
  { code: '06', title: 'Selection & Checklist Rows (AppToggleRow, AppCheckboxRow)' },
  { code: '07', title: 'Cards & Headers (AppCard, AppSectionHeader, appCardStyle, appSubCardStyle)' },
  { code: '08', title: 'Metric Tiles & Financial Display (AppMetricTile)' },
  { code: '09', title: 'Feedback & Empty States (AppEmptyState, LoadingView)' },
  { code: '10', title: 'Chart HUDs & Annotations (badgeMarker, badgeMarkerSmall)' },
  { code: '11', title: 'Typography System (AppTypography - Zero Raw Fonts)' },
  { code: '12', title: 'Spacing & Layout Grid (AppSpacing Scale)' },
  { code: '13', title: 'Modal Sheet Presentation (AppSheetContainer, ModalCloseButton)' },
  { code: '14', title: 'Confirmation Dialogs (appConfirmationAlert, appInfoAlert)' },
  { code: '15', title: 'Loading Shimmer Skeletons (AppSkeleton)' },
  { code: '16', title: 'Native Haptics Feedback (NativeHaptics - Zero Raw UIKit)' },
  { code: '17', title: 'Animation Presets (AppAnimations Presets)' },
  { code: '18', title: 'Financial Formatters (Formatters - Zero Raw Concat)' },
  { code: '19', title: 'Semantic Colors (AppColors - Zero Ad-hoc Hex in Features)' },
  { code: '20', title: 'Timezone Alignment (env.currentTimeZone, JournalIds)' },
  { code: '21', title: 'Minimum Touch Targets (44x44pt Apple HIG Bounds)' },
  { code: '22', title: 'Safe Keyboard Handling (ScrollView Form Safety)' },
  { code: '23', title: 'Offline & Network Resilience (TradeDataStore Cache-First)' },
  { code: '24', title: 'Zero Unsafe Force-Unwrapping (Defensive Optionals & Safe Math)' },
  { code: '25', title: 'Push Notifications & Alerts (AppNotificationManager)' },
  { code: '26', title: 'Source Size Limits (Max 800 Lines per File)' },
  { code: '27', title: 'Alerting Architecture (AppNotificationCoordinator - Zero Emoji)' }
];

standardRegistry.forEach(std => {
  const stdPrefix = `Standard ${std.code}`;
  const catViolations = violations.filter(v => v.std.startsWith(stdPrefix));
  const status = catViolations.length === 0 ? '✅ 100% COMPLIANT' : `❌ ${catViolations.length} VIOLATIONS`;
  const label = `[Standard ${std.code}] ${std.title}`;
  console.log(`${label.padEnd(72, '.')} ${status}`);
});

if (sizeWarnings.length > 0) {
  console.log(`\n⚠️  Standard 26 advisory: ${sizeWarnings.length} function(s) exceed ${WARN_FUNCTION_LINES} lines (non-blocking):`);
  sizeWarnings
    .sort((a, b) => b.length - a.length)
    .forEach(w => console.log(`    ${w.file}:${w.line} (${w.length} lines)`));
}

console.log('\n========================================================================');
if (violations.length > 0) {
  console.error(`❌ BLOCKED BY GITHUB CI: Found ${violations.length} architectural violation(s)!\n`);
  violations.forEach((v, idx) => {
    console.error(`[Violation ${idx + 1}] [${v.std}] [${v.rule}]`);
    console.error(`    File:   ${v.file}:${v.line}`);
    console.error(`    Code:   ${v.code}`);
    console.error(`    Fix:    ${v.fix}\n`);
  });
  console.error('⛔ Commit rejected: All code must adhere to the 27 Architectural Standards.');
  process.exit(1);
} else {
  console.log('✅ PASS: 100% compliance across all 27 Architectural Standards!');
  process.exit(0);
}
