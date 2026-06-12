// Snapshot the current DailyShowcase as a numbered, immutable edition and
// upsert it into the manifest. Prints the zero-padded slug on stdout so the
// regen pipeline can reference the frozen page path.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const srcFile = resolve(root, 'src/components/DailyShowcase.astro');
const editionsDir = resolve(root, 'src/editions');
const manifestFile = resolve(root, 'src/data/editions.json');

const src = readFileSync(srcFile, 'utf8');

const pickStr = (key) => {
  const m = src.match(new RegExp('\\b' + key + "\\s*:\\s*'([^']*)'"));
  return m ? m[1] : '';
};
const noMatch = src.match(/\bno\s*:\s*(\d+)/);
const no = noMatch ? parseInt(noMatch[1], 10) : NaN;
if (!Number.isInteger(no)) {
  console.error('archive-edition: could not read edition.no from DailyShowcase.astro');
  process.exit(1);
}
const slug = String(no).padStart(3, '0');
const entry = {
  no,
  slug,
  date: pickStr('date'),
  title: pickStr('title'),
  subtitle: pickStr('subtitle'),
};

// Freeze the component as src/editions/NNN.astro (immutable copy).
mkdirSync(editionsDir, { recursive: true });
writeFileSync(resolve(editionsDir, `${slug}.astro`), src);

// Upsert manifest, keep ascending by edition number.
let list = [];
try {
  list = JSON.parse(readFileSync(manifestFile, 'utf8'));
  if (!Array.isArray(list)) list = [];
} catch {
  list = [];
}
list = list.filter((e) => e.no !== no);
list.push(entry);
list.sort((a, b) => a.no - b.no);

mkdirSync(dirname(manifestFile), { recursive: true });
writeFileSync(manifestFile, JSON.stringify(list, null, 2) + '\n');

process.stdout.write(slug);
