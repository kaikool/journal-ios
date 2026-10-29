const fs = require('fs');
const path = require('path');

function checkFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  let openBraces = 0, openParens = 0, openBrackets = 0;
  let inString = false, inMultilineComment = false;
  let line = 1, col = 0;

  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    col++;
    if (ch === '\n') {
      line++;
      col = 0;
    }

    if (inMultilineComment) {
      if (ch === '*' && content[i + 1] === '/') {
        inMultilineComment = false;
        i++;
      }
      continue;
    }

    if (inString) {
      if (ch === '\\') {
        i++; // skip escaped char
        continue;
      }
      if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '/' && content[i + 1] === '/') {
      // skip until newline
      while (i < content.length && content[i] !== '\n') i++;
      line++;
      col = 0;
      continue;
    }

    if (ch === '/' && content[i + 1] === '*') {
      inMultilineComment = true;
      i++;
      continue;
    }

    if (ch === '"') {
      // check for multiline triple quotes
      if (content[i + 1] === '"' && content[i + 2] === '"') {
        i += 2;
        while (i < content.length && !(content[i] === '"' && content[i + 1] === '"' && content[i + 2] === '"')) {
          if (content[i] === '\n') { line++; col = 0; }
          i++;
        }
        i += 2;
        continue;
      }
      inString = true;
      continue;
    }

    if (ch === '{') openBraces++;
    else if (ch === '}') {
      openBraces--;
      if (openBraces < 0) return { error: `Extra closing brace '}' at line ${line}, col ${col}` };
    }
    else if (ch === '(') openParens++;
    else if (ch === ')') {
      openParens--;
      if (openParens < 0) return { error: `Extra closing paren ')' at line ${line}, col ${col}` };
    }
    else if (ch === '[') openBrackets++;
    else if (ch === ']') {
      openBrackets--;
      if (openBrackets < 0) return { error: `Extra closing bracket ']' at line ${line}, col ${col}` };
    }
  }

  if (openBraces !== 0) return { error: `Unclosed brace '{' (count: ${openBraces})` };
  if (openParens !== 0) return { error: `Unclosed paren '(' (count: ${openParens})` };
  if (openBrackets !== 0) return { error: `Unclosed bracket '[' (count: ${openBrackets})` };
  return null;
}

function walkDir(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  for (const f of files) {
    const fullPath = path.join(dir, f);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      if (f !== '.git' && f !== '.build' && f !== 'DerivedData' && f !== 'node_modules' && f !== 'source-repo') {
        walkDir(fullPath, fileList);
      }
    } else if (f.endsWith('.swift')) {
      fileList.push(fullPath);
    }
  }
  return fileList;
}

const swiftFiles = [
  ...walkDir('./TradeJournal/Sources'),
  ...walkDir('./TradeJournal/Tests')
];
console.log(`Checking ${swiftFiles.length} Swift files...`);
let errors = 0;
for (const file of swiftFiles) {
  const res = checkFile(file);
  if (res && res.error) {
    console.error(`ERROR in ${file}: ${res.error}`);
    errors++;
  }
}

if (errors === 0) {
  console.log(`All ${swiftFiles.length} Swift files passed balanced syntax check!`);
} else {
  console.error(`Found ${errors} syntax errors.`);
  process.exit(1);
}
