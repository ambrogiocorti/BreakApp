import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {schoolRequiresGeolocation} from '../../src/js/core/geolocation.js';

const fakeClient=result=>({from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>result})})})});

test('school GPS is enabled by default and any read error fails closed',async()=>{
 assert.equal(await schoolRequiresGeolocation(fakeClient({data:{require_geolocation:true}}),'s'),true);
 assert.equal(await schoolRequiresGeolocation(fakeClient({data:{require_geolocation:false}}),'s'),false);
 assert.equal(await schoolRequiresGeolocation(fakeClient({data:null}),'s'),true);
 assert.equal(await schoolRequiresGeolocation(fakeClient({error:{message:'denied'}}),'s'),true);
 assert.equal(await schoolRequiresGeolocation(null,'s'),true);
});

test('both confirmation flows rely on the DB policy and send null GPS when disabled',()=>{
 const individual=readFileSync(new URL('../../src/js/features/orders/orders.js',import.meta.url),'utf8');
 const groups=readFileSync(new URL('../../src/js/features/groups/groups.js',import.meta.url),'utf8');
 const sql=readFileSync(new URL('../../supabase/migrations/20261109141732_school_geolocation_toggle.sql',import.meta.url),'utf8');
 assert.match(individual,/const requireGPS=await schoolRequiresGeolocation/);
 assert.match(individual,/p_latitude:loc\?\.coords\.latitude\?\?null/);
 assert.match(groups,/if\(await schoolRequiresGeolocation\(client,detail\.school_id\)\)/);
 assert.match(groups,/p_latitude:null,p_longitude:null,p_accuracy_m:null,p_observed_at:null/);
 assert.match(sql,/default true/);
 assert.match(sql,/if v_school\.require_geolocation then/);
 assert.match(sql,/role_code='school_admin'/);
 assert.match(sql,/aal2/);
});
