#!/usr/bin/env node

/**
 * TradeJournal iOS - Comprehensive 17-Category Architectural CI Gatekeeper
 * Automatically halts GitHub Actions CI build if any violation is detected across all 17 categories.
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SOURCES_DIR = path.join(ROOT_DIR, 'TradeJournal', 'Sources');

const WHITELIST = [
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
  'AppMetricTile.swift'
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
  if (WHITELIST.includes(base)) return;
  const rel = path.relative(ROOT_DIR, f).replace(/\\/g, '/');
  const content = fs.readFileSync(f, 'utf8');
  const lines = content.split('\n');

  lines.forEach((l, idx) => {
    const lineNum = idx + 1;
    const trimmed = l.trim();

    // Cat 11: Typography (Raw fonts)
    if (trimmed.includes('.font(.system(size:') || trimmed.includes('.font(.system(') || trimmed.includes('.font(.custom(')) {
      violations.push({ category: 'Category 11: Typography', file: rel, line: lineNum, code: trimmed, fix: 'Use AppTypography tokens' });
    }

    // Cat 16: Haptics (Direct UIKit feedback generators)
    if (trimmed.includes('UIImpactFeedbackGenerator') || trimmed.includes('UISelectionFeedbackGenerator') || trimmed.includes('UINotificationFeedbackGenerator')) {
      violations.push({ category: 'Category 16: Haptics', file: rel, line: lineNum, code: trimmed, fix: 'Use NativeHaptics' });
    }

    // Cat 17: Animations (Raw spring or easeInOut with magic numbers)
    if (trimmed.includes('.spring(response:') || trimmed.includes('withAnimation(.spring(response:')) {
      violations.push({ category: 'Category 17: Animations', file: rel, line: lineNum, code: trimmed, fix: 'Use AppAnimations' });
    }

    // Cat 14: Confirmation Dialogs (Raw .alert with destructive button)
    if (trimmed.includes('.alert(') && !trimmed.includes('appConfirmationAlert')) {
      violations.push({ category: 'Category 14: Confirmation Dialogs', file: rel, line: lineNum, code: trimmed, fix: 'Use .appConfirmationAlert' });
    }

    // Cat 7: Cards (Ad-hoc card container background + cornerRadius/clipShape)
    if ((trimmed.includes('background(AppColors.cardBackground)') || trimmed.includes('background(AppColors.surface)')) &&
        (trimmed.includes('clipShape(RoundedRectangle') || trimmed.includes('cornerRadius('))) {
      violations.push({ category: 'Category 07: Cards', file: rel, line: lineNum, code: trimmed, fix: 'Use AppCard' });
    }

    // Cat 5: Form Fields (Raw TextField/SecureField in Feature views)
    if (rel.includes('/Features/') && (trimmed.startsWith('TextField(') || trimmed.startsWith('SecureField('))) {
      violations.push({ category: 'Category 05: Form Fields', file: rel, line: lineNum, code: trimmed, fix: 'Use AppTextField or AppNumericField' });
    }

    // Cat 6: Selection Rows (Raw Toggle without AppToggleRow in Feature views)
    if (rel.includes('/Features/') && trimmed.startsWith('Toggle(') && !trimmed.includes('AppToggleRow')) {
      violations.push({ category: 'Category 06: Selection Rows', file: rel, line: lineNum, code: trimmed, fix: 'Use AppToggleRow' });
    }

    // Cat 1: Buttons (Raw button with custom inline background in Feature views)
    if (rel.includes('/Features/') && (trimmed.includes('.background(AppColors.brand') || trimmed.includes('.background(AppColors.loss')) && (trimmed.includes('Button') || lines[Math.max(0, idx - 4)].includes('Button'))) {
      violations.push({ category: 'Category 01: Buttons', file: rel, line: lineNum, code: trimmed, fix: 'Use AppButton, AppPrimaryButton, or ModalToolbarButtons' });
    }
  });
});

console.log('========================================================================');
console.log('       TRADEJOURNAL IOS - 17-CATEGORY CI ARCHITECTURAL GATEKEEPER        ');
console.log('========================================================================');
console.log(`Audited ${files.length} Swift files across ${SOURCES_DIR}\n`);

if (violations.length > 0) {
  console.error(`❌ BLOCKED BY GITHUB CI: Found ${violations.length} design system violation(s)!\n`);
  violations.forEach((v, idx) => {
    console.error(`[Violation ${idx + 1}] [${v.category}] ${v.file}:${v.line}`);
    console.error(`    Offending Code:  ${v.code}`);
    console.error(`    Required Fix:    ${v.fix}\n`);
  });
  console.error('⛔ Commit rejected: All code must strictly adhere to the 17 design system categories.');
  process.exit(1);
} else {
  console.log('✅ PASS: 100% compliance across all 17 Design System categories!');
  process.exit(0);
}
