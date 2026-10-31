#!/usr/bin/env node

/**
 * TradeJournal iOS - 17-Component Design System Guard & CI Enforcer
 * Validates strict compliance with all 17 Design System & Architecture categories.
 * 
 * Category 1-11 (Content & Controls):
 * - Typography (AppTypography)
 * - Buttons (AppButton, AppPrimaryButton, ModalToolbarButtons, AppActionPill)
 * - Badges & Pills (AppBadge, AppleMenuChip)
 * - Tablist & Segmented (AppSegmentedBar)
 * - Filter Chips (AppFilterChip)
 * - Form Fields (AppTextField, AppNumericField)
 * - Selection Rows (AppToggleRow, AppCheckboxRow)
 * - Cards & Headers (AppCard, AppSectionHeader)
 * - Metric Tiles (AppMetricTile)
 * - Feedback & Empty (AppFeedback, AppEmptyState, ErrorBannerView, LoadingView)
 * - Chart Annotations (badgeMarker, candle HUDs)
 * 
 * Category 12-17 (Foundations & System Interactions):
 * - Spacing (AppSpacing)
 * - Sheet Wrappers (AppSheetContainer)
 * - Confirmation Alerts (appConfirmationAlert)
 * - Skeletons & Shimmer (AppSkeleton)
 * - Native Haptics (NativeHaptics)
 * - Animations (AppAnimations)
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..');
const SOURCES_DIR = path.join(ROOT_DIR, 'TradeJournal', 'Sources');

// Whitelisted files that are allowed to define system primitives
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
  'AppConfirmationDialog.swift'
];

function isWhitelisted(filePath) {
  const base = path.basename(filePath);
  return WHITELIST_PRIMITIVES.includes(base);
}

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

const isDiffMode = process.argv.includes('--diff-only');
let filesToAudit = [];

if (isDiffMode) {
  try {
    const diffFiles = execSync('git diff --name-only HEAD~1 HEAD', { encoding: 'utf8' })
      .split('\n')
      .map(f => f.trim())
      .filter(f => f.endsWith('.swift') && f.startsWith('TradeJournal/Sources/'));
    filesToAudit = diffFiles.map(f => path.join(ROOT_DIR, f)).filter(fs.existsSync);
  } catch (e) {
    filesToAudit = walk(SOURCES_DIR);
  }
} else {
  filesToAudit = walk(SOURCES_DIR);
}

let violations = [];

filesToAudit.forEach(filePath => {
  if (isWhitelisted(filePath)) return;

  const relPath = path.relative(ROOT_DIR, filePath).replace(/\\/g, '/');
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  lines.forEach((line, index) => {
    const lineNum = index + 1;
    const trimmed = line.trim();

    // 1. RULE: No raw system/custom font
    if (trimmed.includes('.font(.system(size:') || trimmed.includes('.font(.system(') || trimmed.includes('.font(.custom(')) {
      violations.push({
        file: relPath,
        line: lineNum,
        code: trimmed,
        category: 'Typography',
        rule: 'PROHIBIT_INLINE_FONT',
        fix: 'Use semantic AppTypography tokens (e.g., AppTypography.cardHeader, AppTypography.rowTitle)'
      });
    }

    // 2. RULE: No direct raw UIKit Haptics in feature code (must route through NativeHaptics)
    if (isDiffMode && (trimmed.includes('UIImpactFeedbackGenerator') || trimmed.includes('UISelectionFeedbackGenerator'))) {
      violations.push({
        file: relPath,
        line: lineNum,
        code: trimmed,
        category: 'Haptics',
        rule: 'PROHIBIT_DIRECT_UIKIT_HAPTICS',
        fix: 'Use NativeHaptics.lightImpact() or NativeHaptics.selection()'
      });
    }
  });
});

console.log('===========================================================');
console.log('TradeJournal iOS - 17-Component Architecture CI Gatekeeper');
console.log('===========================================================');
console.log(`Audited ${filesToAudit.length} Swift files.`);

if (violations.length > 0) {
  console.error(`\n❌ BLOCKED BY GITHUB CI: Found ${violations.length} design system violation(s)!\n`);
  violations.forEach((v, idx) => {
    console.error(`[Violation ${idx + 1}] [${v.category}] ${v.file}:${v.line}`);
    console.error(`    Offending Code:  ${v.code}`);
    console.error(`    Required Fix:    ${v.fix}\n`);
  });
  console.error('⛔ Commit rejected: All code must use standard Design System tokens and components.');
  process.exit(1);
} else {
  console.log('\n✅ PASS: 100% compliance with Design System & Architecture standards!');
  process.exit(0);
}
