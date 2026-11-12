import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { contextsFromMemberships } from '../../src/js/features/shell/workspace.js';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');

test('workspace propagates the authoritative MFA verification state',()=>{
 const source=read('src/js/features/shell/workspace.js');
 assert.match(source,/verified:Boolean\(active\.verified\)/);
 const school='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 const entries=[{school_id:school,role_assignments:[{role_code:'school_admin'}]}];
 const schools=[{id:school,name:'School'}];
 assert.equal(contextsFromMemberships(entries,schools,false,false)
   .find(x=>x.role==='school_admin').verified,false);
 assert.equal(contextsFromMemberships(entries,schools,true,false)
   .find(x=>x.role==='school_admin').verified,true);
});

test('dashboard never promotes a context to verified on its own',()=>{
 const source=read('src/js/features/shell/dashboards.js');
 assert.doesNotMatch(source,/context\.verified\s*=\s*true/);
 assert.match(source,/context\?\.role==='school_admin'&&context\.verified/);
 const platform=read('src/js/features/shell/platform-dashboard.js');
 assert.doesNotMatch(platform,/context\.verified\s*=\s*true/);
 assert.match(platform,/context\?\.role==='platform_admin'&&context\.verified/);
});
