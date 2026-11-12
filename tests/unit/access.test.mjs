import test from 'node:test';
import assert from 'node:assert/strict';
import { loadSchoolAccess, roleLabel } from '../../src/js/features/auth/access.js';

test('etichette dei ruoli per scuola', () => {
  assert.equal(roleLabel('school_admin'), 'Admin scuola');
  assert.equal(roleLabel('bartender'), 'Barista');
  assert.equal(roleLabel('warehouse_manager'), 'Magazziniere');
  assert.equal(roleLabel('customer'), 'Cliente');
  assert.equal(roleLabel('unexpected'), 'Ruolo non riconosciuto');
});

test('un utente senza scuola non richiede l’elenco dei bar', async () => {
  const calls = [];
  const query = {
    select() { return this; },
    eq(column, value) { calls.push([column, value]); return this; },
    then(resolve, reject) { return Promise.resolve({ data: [], error: null }).then(resolve, reject); }
  };
  const client = { from(table) {
    assert.equal(table, 'school_memberships');
    return query;
  } };
  assert.deepEqual(await loadSchoolAccess(client, 'user-a'), { memberships: [], bars: [] });
  assert.deepEqual(calls, [['user_id', 'user-a'], ['membership_status', 'active']]);
});

test('l’accesso alle scuole viene letto da Supabase, senza ruoli inventati', async () => {
  const membership = {
    id: 'm-1', school_id: 'school-1', membership_status: 'active',
    schools: { id: 'school-1', name: 'Scuola test', slug: 'scuola-test' },
    role_assignments: [{ role_code: 'school_admin' }]
  };
  const fromCalls = [];
  function query(response) {
    return {
      select() { return this; },
      eq() { return this; },
      in(column, ids) { assert.equal(column, 'school_id'); assert.deepEqual(ids, ['school-1']); return this; },
      order() { return this; },
      then(resolve, reject) { return Promise.resolve(response).then(resolve, reject); }
    };
  }
  const client = {
    from(table) {
      fromCalls.push(table);
      return table === 'school_memberships'
        ? query({ data: [membership], error: null })
        : query({ data: [{ id: 'bar-1', school_id: 'school-1', name: 'Bar test' }], error: null });
    }
  };
  const access = await loadSchoolAccess(client, 'user-1');
  assert.deepEqual(fromCalls, ['school_memberships', 'bars']);
  assert.equal(access.memberships[0].role_assignments[0].role_code, 'school_admin');
  assert.equal(access.bars[0].name, 'Bar test');
});
