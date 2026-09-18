import { readFileSync } from 'node:fs';

// Provider Monitor has two renderers, but one product. These are not arbitrary CSS
// preferences: each number is the current macOS 1.15.0 NotchLayout value after
// Design.scale (44 / 117) is applied and rounded to a CSS pixel. If Windows drifts,
// a green build must not be allowed to call the two apps visually equivalent again.
const notch = readFileSync(new URL('../codenotch/ui/notch.html', import.meta.url), 'utf8');
const settings = readFileSync(new URL('../codenotch/ui/settings.html', import.meta.url), 'utf8');

const requiredNotchTokens = new Map([
  ['--notch-depth', '70px'],
  ['--ring-size', '44px'],
  ['--cell-gap', '31px'],
  ['--glyph-size', '17px'],
  ['--card-width', '226px'],
  ['--card-radius', '19px'],
  ['--card-padding', '12px'],
  ['--badge-height', '12px'],
]);

const missing = [];
for (const [name, value] of requiredNotchTokens) {
  if (!notch.includes(`${name}:${value}`)) missing.push(`${name}:${value}`);
}

for (const title of ['Accounts', 'Appearance', 'Notifications', 'General', 'About']) {
  if (!settings.includes(`>${title}</button>`)) missing.push(`settings section: ${title}`);
}

for (const copy of [
  "'Usage':'사용량'",
  "'Current session':'현재 세션'",
  "'Weekly limit':'주간 한도'",
  "'5-hour limit':'5시간 한도'",
  "'Monthly limit':'월간 한도'",
]) {
  if (!notch.includes(copy)) missing.push(`Korean hover copy: ${copy}`);
}

if (!settings.includes('--settings-sidebar:200px')) missing.push('--settings-sidebar:200px');
if (!settings.includes('--selection:#0a84ff')) missing.push('--selection:#0a84ff');
if (!settings.includes('id="percent-basis"')) missing.push('Appearance: ring-number basis control');
if (!settings.includes('id="display-select"')) missing.push('Appearance: target-display control');
if (!notch.includes('svgArc(25,Math.max(0,Math.min(h.used,1))')) {
  missing.push('ring graph must fill by used fraction');
}
if (!notch.includes('width:${(Math.min(w.used,1)*100).toFixed(0)}%')) {
  missing.push('hover bars must fill by used fraction');
}

if (missing.length) {
  console.error('Windows UI is not pinned to the macOS 1.15.0 product geometry:');
  for (const item of missing) console.error(`  - ${item}`);
  process.exit(1);
}

console.log('Windows UI carries the macOS 1.15.0 geometry and settings sections.');
