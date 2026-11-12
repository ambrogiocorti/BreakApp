import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

function collect(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return collect(path);
    return /\.(m?js)$/.test(entry.name) ? [path] : [];
  });
}

const files = ['vite.config.js', ...collect('src'), ...collect('scripts'), ...collect('tests')];
let failures = 0;
for (const file of files) {
  const result = spawnSync(process.execPath, ['--check', file], { stdio: 'inherit' });
  if (result.status !== 0) failures++;
}
if (failures) {
  console.error(`${failures} file con errori di sintassi.`);
  process.exitCode = 1;
} else {
  console.log(`Sintassi valida: ${files.length} file JavaScript.`);
}
