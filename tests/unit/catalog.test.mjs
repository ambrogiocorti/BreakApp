import test from 'node:test';
import assert from 'node:assert/strict';
import { parseEuroToCents, formatEuro, getAdminSchools } from '../../src/js/features/catalog/utils.js';

test('prezzi in euro convertiti senza floating point', () => {
  assert.equal(parseEuroToCents('2,50'), 250);
  assert.equal(parseEuroToCents('0.05'), 5);
  assert.equal(parseEuroToCents('3'), 300);
  assert.equal(parseEuroToCents('3,5'), 350);
  assert.equal(parseEuroToCents('100000'), 10000000);
});
test('prezzi non validi respinti', () => {
  for (const value of ['-2', '0.001', '2e4', '10,999', '', '100001', '2,5€']) {
    assert.throws(() => parseEuroToCents(value));
  }
});
test('visualizzazione monetaria italiana', () => {
  assert.match(formatEuro(250), /2,50/);
  assert.throws(() => formatEuro(2.4));
});
test('solo le scuole con ruolo admin attivo abilitano catalogo', () => {
  const access = {
    memberships: [
      { school_id:'a', membership_status:'active', schools:{name:'Scuola A'}, role_assignments:[{role_code:'school_admin'}] },
      { school_id:'b', membership_status:'active', schools:{name:'Scuola B'}, role_assignments:[{role_code:'customer'}] },
      { school_id:'c', membership_status:'suspended', schools:{name:'Scuola C'}, role_assignments:[{role_code:'school_admin'}] }
    ]
  };
  assert.deepEqual(getAdminSchools(access), [{ id:'a', name:'Scuola A' }]);
});
