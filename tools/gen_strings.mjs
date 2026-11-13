#!/usr/bin/env node
// Builds Resources/Localizable.xcstrings from the LocalSend translation files in Resources/i18n.
//
// SwiftUI treats a plain string literal as a LocalizedStringKey, so the English text in the
// views *is* the key. tools/strings.json maps each of those literals to the matching upstream
// key; everything the upstream project already translated then comes for free.
//
// Run: node tools/gen_strings.mjs   (commit the result; CI re-runs and fails on drift)

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const I18N = 'Resources/i18n';
const OUT = 'Resources/Localizable.xcstrings';
const MAP = JSON.parse(readFileSync('tools/strings.json', 'utf8'));

const LOCALE_MAP = {
  'zh-CN': 'zh-Hans',
  'zh-TW': 'zh-Hant',
  'zh-HK': 'zh-Hant-HK',
  'en-IN': 'en-GB',
  'es-ES': 'es',
  'sr-Cyrl': 'sr-Cyrl',
  'fil-PH': 'fil',
};

function flatten(value, prefix, out) {
  for (const [key, child] of Object.entries(value)) {
    if (key.startsWith('@')) continue;
    const path = prefix ? `${prefix}.${key}` : key;
    if (child && typeof child === 'object') flatten(child, path, out);
    else if (typeof child === 'string') out[path] = child;
  }
  return out;
}

const tables = new Map();
for (const file of readdirSync(I18N)) {
  if (!file.endsWith('.json') || file.startsWith('_')) continue;
  const tag = file.replace(/\.json$/, '');
  tables.set(LOCALE_MAP[tag] ?? tag, flatten(JSON.parse(readFileSync(join(I18N, file), 'utf8')), '', {}));
}

/** Resolves slang's `@:other.key` references inside one locale. */
function resolve(table, key, depth = 0) {
  const raw = table[key];
  if (typeof raw !== 'string' || depth > 4) return undefined;
  if (!raw.startsWith('@:')) return raw;
  return resolve(table, raw.slice(2), depth + 1);
}

const strings = {};
let localized = 0;
for (const [literal, key] of Object.entries(MAP)) {
  if (literal.startsWith('_')) continue;
  const localizations = {};
  for (const [tag, table] of tables) {
    if (tag === 'en') continue;
    const value = resolve(table, key);
    if (value && value !== literal) {
      localizations[tag] = { stringUnit: { state: 'translated', value } };
    }
  }
  if (Object.keys(localizations).length > 0) localized += 1;
  strings[literal] = { localizations };
}

writeFileSync(OUT, JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2) + '\n');
console.log(`entries=${Object.keys(strings).length} localized=${localized} locales=${tables.size}`);
