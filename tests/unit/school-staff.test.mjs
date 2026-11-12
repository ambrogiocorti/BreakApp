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

test('one school and one role is enforced by the database, legacy assignment included',()=>{
 const migration=readFileSync(new URL('../../supabase/migrations/20261106130000_one_school_one_role.sql',import.meta.url),'utf8');
 assert.match(migration,/create unique index school_memberships_one_school_per_user\s+on public\.school_memberships\(user_id\)/);
 assert.match(migration,/create unique index role_assignments_one_role_per_membership\s+on public\.role_assignments\(membership_id\)/);
 assert.match(migration,/return public\.invite_school_staff\(p_school_id,p_email,p_role\)/);
 assert.match(migration,/'admin',v_admin/);
 const ui=readFileSync(new URL('../../src/js/features/operations/completion-ui.js',import.meta.url),'utf8');
 assert.match(ui,/showOnboardingAdmin\(outcome,result\?\.admin\)/);
 assert.doesNotMatch(ui,/Email verificata del primo Admin/);
});
