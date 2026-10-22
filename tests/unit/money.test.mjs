import test from 'node:test';
import assert from 'node:assert/strict';
import { formatEuro } from '../../src/js/core/money.js';

test('mostra esattamente due decimali per un importo in centesimi', () => {
  assert.match(formatEuro(250), /2,50/);
});

test('gestisce zero e importi negativi nei riepiloghi UI', () => {
  assert.match(formatEuro(0), /0,00/);
  assert.match(formatEuro(-125), /1,25/);
});

test('rifiuta numeri con parte frazionaria', () => {
  assert.throws(() => formatEuro(2.5), TypeError);
});
