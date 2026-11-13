#!/usr/bin/env node
// Generates Resources/Localizable.xcstrings from the LocalSend translation files in
// Resources/i18n. The SwiftUI views use the English text as the lookup key, so a string is
// translated when its English value matches a value in en.json — that keeps the source
// readable and inherits all ~57 locales the upstream project ships.
//
// Run: node tools/gen_strings.mjs  (commit the result; CI re-runs it and fails on drift)

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const I18N = 'Resources/i18n';
const SOURCES = ['Sources', 'ShareExtension'];
const OUT = 'Resources/Localizable.xcstrings';

// Apple wants script-based Chinese tags; the upstream files use region tags.
const LOCALE_MAP = {
  'zh-CN': 'zh-Hans',
  'zh-TW': 'zh-Hant',
  'zh-HK': 'zh-Hant-HK',
  'en-IN': 'en-GB',
  'es-ES': 'es',
  'pt-BR': 'pt-BR',
  'pt-PT': 'pt-PT',
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

function loadLocale(file) {
  return flatten(JSON.parse(readFileSync(join(I18N, file), 'utf8')), '', {});
}

const files = readdirSync(I18N).filter((f) => f.endsWith('.json') && !f.startsWith('_'));
const locales = new Map(); // appleTag -> flattened table
for (const file of files) {
  const tag = file.replace(/\.json$/, '');
  locales.set(LOCALE_MAP[tag] ?? tag, loadLocale(file));
}
const english = locales.get('en') ?? loadLocale('en.json');
if (!english || Object.keys(english).length === 0) throw new Error('en.json is missing');

// value -> first key that carries it
const byValue = new Map();
for (const [key, value] of Object.entries(english)) {
  if (!byValue.has(value)) byValue.set(value, key);
}

function collectLiterals(dir, out) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) collectLiterals(path, out);
    else if (entry.name.endsWith('.swift')) {
      const body = readFileSync(path, 'utf8');
      const pattern = /"((?:[^"\\n]|\.)*)"/g;
      let match;
      while ((match = pattern.exec(body)) !== null) {
        const literal = match[1];
        if (!literal || literal.includes('\(')) continue;
        out.add(literal);
      }
    }
  }
  return out;
}

const literals = new Set();
for (const dir of SOURCES) collectLiterals(dir, literals);

const strings = {};
let matched = 0;
for (const literal of [...literals].sort()) {
  const key = byValue.get(literal);
  if (!key) continue;
  matched += 1;
  const localizations = {};
  for (const [tag, table] of locales) {
    if (tag === 'en') continue;
    const value = table[key];
    if (typeof value === 'string' && value && value !== literal) {
      localizations[tag] = { stringUnit: { state: 'translated', value } };
    }
  }
  strings[literal] = Object.keys(localizations).length > 0 ? { localizations } : {};
}

const catalog = { sourceLanguage: 'en', strings, version: '1.0' };
writeFileSync(OUT, JSON.stringify(catalog, null, 2) + '\n');
console.log(`literals=${literals.size} matched=${matched} locales=${locales.size} -> ${OUT}`);
