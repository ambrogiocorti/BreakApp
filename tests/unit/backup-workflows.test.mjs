import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

// I backup del database e dello Storage producono dump dell'intero database.
// Su un repository PUBBLICO gli artifact di Actions sono scaricabili da chiunque
// abbia accesso in lettura: questi workflow devono rifiutarsi di girare lì.
for (const file of [
  '.github/workflows/encrypted-backup.yml',
  '.github/workflows/encrypted-storage-backup.yml',
]) {
  test(`${file} si rifiuta di girare su un repository pubblico`, () => {
    const workflow = read(file);
    assert.match(workflow, /Refuse to run on a public repository/);
    assert.match(workflow, /repos\/\$\{\{ github\.repository \}\}/);
    assert.match(workflow, /--jq '\.private'/);
    assert.match(workflow, /if \[ "\$private" != "true" \]; then/);
    assert.match(workflow, /exit 1/);
    // Nessun segreto esposto in chiaro nel workflow.
    assert.doesNotMatch(workflow, /sk_test_|sk_live_|service_role/);
  });
}
