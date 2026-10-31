#!/usr/bin/env node

/**
 * TradeJournal iOS - Automated Design System & Typography Linter
 * Ensures strict adherence to AppTypography and DesignSystem reusable components.
 * 
 * Rules Enforced:
 * 1. Zero raw font calls: No .font(.system(size:...)) or .font(.custom(...)) outside AppTypography.swift.
 * 2. Proper semantic typography token usage.
 * 3. No inline hardcoded typography styling.
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SOURCES_DIR = path.join(ROOT_DIR, 'TradeJournal', 'Sources');

function walk(dir) {
  let results = [];
  if (!fs.existsSync(dir)) return results;
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(walk(fullPath));
    } else if (fullPath.endsWith('.swift')) {
      results.push(fullPath);
    }
  });
  return results;
}

const files = walk(SOURCES_DIR);
let violations = [];

files.forEach(filePath => {
  // Allow AppTypography.swift itself to define system fonts
  if (filePath.endsWith('AppTypography.swift')) return;

  const relPath = path.relative(ROOT_DIR, filePath).replace(/\\/g, '/');
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  lines.forEach((line, index) => {
    const lineNum = index + 1;
    const trimmed = line.trim();

    // 1. Raw .font(.system(size: ...))
    if (trimmed.includes('.font(.system(size:') || trimmed.includes('.font(.system(')) {
      violations.push({
        file: relPath,
        line: lineNum,
        code: trimmed,
        rule: 'RULE_NO_RAW_SYSTEM_FONT',
        message: 'Direct .font(.system(...)) is prohibited. Use semantic AppTypography tokens (e.g., AppTypography.cardHeader, AppTypography.rowTitle).'
      });
    }

    // 2. Raw .font(.custom(...))
    if (trimmed.includes('.font(.custom(')) {
      violations.push({
        file: relPath,
        line: lineNum,
        code: trimmed,
        rule: 'RULE_NO_CUSTOM_FONT',
        message: 'Direct .font(.custom(...)) is prohibited. Define and use AppTypography tokens.'
      });
    }

    // 3. Raw Apple system text styles if used inline when AppTypography tokens exist
    const rawHIGFonts = ['.font(.largeTitle)', '.font(.title)', '.font(.title2)', '.font(.title3)'];
    rawHIGFonts.forEach(rf => {
      if (trimmed.includes(rf)) {
        violations.push({
          file: relPath,
          line: lineNum,
          code: trimmed,
          rule: 'RULE_USE_APP_TYPOGRAPHY',
          message: `Replace ${rf} with semantic AppTypography token (e.g. AppTypography.pageTitle, AppTypography.sectionHeader).`
        });
      }
    });
  });
});

console.log('====================================================');
console.log('TradeJournal iOS - Design System & Typography Guard');
console.log('====================================================');
console.log(`Audited ${files.length} Swift files across ${SOURCES_DIR}`);

if (violations.length > 0) {
  console.error(`\n❌ Found ${violations.length} design system violation(s):\n`);
  violations.forEach((v, idx) => {
    console.error(`[${idx + 1}] ${v.file}:${v.line} (${v.rule})`);
    console.error(`    Code:    ${v.code}`);
    console.error(`    Fix:     ${v.message}\n`);
  });
  console.error('Build rejected: Please fix all design system violations before pushing.');
  process.exit(1);
} else {
  console.log('\n✅ PASS: 100% of Swift files comply with AppTypography & DesignSystem standards!');
  process.exit(0);
}
