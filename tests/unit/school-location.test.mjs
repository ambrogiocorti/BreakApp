import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {mapLink} from '../../src/js/features/orders/admin-setup.js';

test('map link points to the exact saved coordinates and rejects invalid ones',()=>{
 assert.equal(mapLink('45.521234','9.3301'),
  'https://www.openstreetmap.org/?mlat=45.521234&mlon=9.330100#map=18/45.521234/9.330100');
 assert.equal(mapLink('',''),null);
 assert.equal(mapLink('91','9'),null);
 assert.equal(mapLink('45','181'),null);
});

test('address and settings changes are audited and restricted to the school admin with 2FA',async()=>{
 const sql=await readFile(new URL('../../supabase/migrations/20261108230000_school_location_address_audit.sql',import.meta.url),'utf8');
 assert.match(sql,/after update on public\.schools/);
 assert.match(sql,/insert into app_private\.school_settings_audit/);
 assert.match(sql,/aal2/);
 assert.match(sql,/role_code='school_admin'/);
 assert.match(sql,/revoke all on app_private\.school_settings_audit from public,anon,authenticated/);
});

test('the admin form saves the address and offers the device position',async()=>{
 const html=await readFile(new URL('../../index.html',import.meta.url),'utf8');
 assert.match(html,/id="ops-address"[^>]*maxlength="200"/);
 assert.match(html,/id="ops-use-position"/);
 assert.match(html,/id="ops-map-link"[^>]*rel="noopener noreferrer"/);
});
