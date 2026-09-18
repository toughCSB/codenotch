import { existsSync, readFileSync } from 'node:fs';

// Provider Monitor has two renderers, but one product. These are not arbitrary CSS
// preferences: each number is the current macOS NotchLayout value after
// Design.scale (44 / 117) is applied and rounded to a CSS pixel. If Windows drifts,
// a green build must not be allowed to call the two apps visually equivalent again.
const notch = readFileSync(new URL('../codenotch/ui/notch.html', import.meta.url), 'utf8');
const settings = readFileSync(new URL('../codenotch/ui/settings.html', import.meta.url), 'utf8');
const main = readFileSync(new URL('../codenotch/src/main.rs', import.meta.url), 'utf8');
const tauri = JSON.parse(readFileSync(new URL('../codenotch/tauri.conf.json', import.meta.url), 'utf8'));

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
if (!notch.includes('svgArc(25,ringPercent(h),tone(h.used),5)')) {
  missing.push('ring graph must follow the selected percent basis');
}
if (!notch.includes('width:${(ringPercent(w)*100).toFixed(0)}%')) {
  missing.push('hover bars must follow the selected percent basis');
}
if (!notch.includes("provider==='grok' && w.id==='credits'")) missing.push('Grok credits must carry its weekly badge');
if (!settings.includes('[hidden]{display:none!important}')) missing.push('hidden update rows must stay hidden');
if (!settings.includes('white-space:nowrap')) missing.push('sidebar quit label must stay on one line');
const windowsProviders = [
  'claude', 'codex', 'cursor', 'gemini', 'grok', 'opencode', 'glm', 'devin',
  'commandcode', 'kimi', 'copilot', 'kiro',
];
for (const provider of windowsProviders) {
  if (!main.includes(`"${provider}"`)) missing.push(`Rust provider catalog: ${provider}`);
  if (!settings.includes(`'${provider}'`)) missing.push(`settings provider catalog: ${provider}`);
  if (!notch.includes(`get_${provider}`) && provider !== 'claude' && provider !== 'gemini') {
    missing.push(`notch provider binding: ${provider}`);
  }
}
const settingsWindow = tauri.app.windows.find(window => window.label === 'settings');
if (settingsWindow?.width !== 680 || settingsWindow?.height !== 520 || settingsWindow?.resizable !== false) {
  missing.push('settings window must stay at the macOS 680x520 layout');
}

const sameBytes = (left, right) => readFileSync(new URL(left, import.meta.url))
  .equals(readFileSync(new URL(right, import.meta.url)));
if (!sameBytes('../../Sources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png', '../codenotch/icons/icon.png')) {
  missing.push('Windows app PNG must be the macOS Provider Monitor icon');
}
if (!sameBytes('../../Sources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png', '../codenotch/icons/tray-color.png')) {
  missing.push('Windows tray mark must be the macOS Provider Monitor icon');
}
if (!sameBytes('../../Sources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png', '../codenotch/ui/tray.png')) {
  missing.push('Windows settings mark must be the macOS Provider Monitor icon');
}
if (existsSync(new URL('../codenotch/icons/tray.png', import.meta.url))) {
  missing.push('retired CodeNotch tray.png must not remain');
}

if (missing.length) {
  console.error('Windows UI is not pinned to the macOS 1.15.0 product geometry:');
  for (const item of missing) console.error(`  - ${item}`);
  process.exit(1);
}

console.log('Windows UI carries the current macOS geometry and settings sections.');
