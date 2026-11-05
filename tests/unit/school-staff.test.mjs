import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {staffRoleOptions,roleLabel} from '../../src/js/features/operations/school-staff.js';

test('a school admin can only add bartenders and warehouse managers',()=>{
 assert.deepEqual(staffRoleOptions(false).map(([role])=>role),['bartender','warehouse_manager']);
 assert.deepEqual(staffRoleOptions(true).map(([role])=>role),['school_admin','bartender','warehouse_manager']);
 assert.equal(roleLabel('warehouse_manager'),'Magazziniere');
});

test('staff panels use the invitation RPCs, never a client-side role write',()=>{
 const ui=readFileSync(new URL('../../src/js/features/operations/school-staff.js',import.meta.url),'utf8');
 for(const rpc of ['list_school_staff','invite_school_staff','update_school_staff_invite','remove_school_staff_invite','claim_school_staff_invite'])
  assert.match(ui,new RegExp("'"+rpc+"'"));
 assert.doesNotMatch(ui,/from\('(school_memberships|role_assignments)'\)\.(insert|update|upsert|delete)/);
 const migration=readFileSync(new URL('../../supabase/migrations/20261105180000_school_staff_invitations.sql',import.meta.url),'utf8');
 assert.match(migration,/p_role in \('bartender','warehouse_manager'\) and app_private\.can_manage_support_school/);
 assert.match(migration,/revoke all on app_private\.school_staff_invites from public,anon,authenticated/);
});
