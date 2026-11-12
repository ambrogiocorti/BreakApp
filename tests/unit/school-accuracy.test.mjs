import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {accuracyLimit,schoolAccuracyLimit,accuratePosition,DEFAULT_ACCURACY_M} from '../../src/js/core/geolocation.js';

test('accuracyLimit accepts 10–1000 m and falls back to 100 m',()=>{
  assert.equal(DEFAULT_ACCURACY_M,100);
  assert.equal(accuracyLimit(1000),1000);
  assert.equal(accuracyLimit(10),10);
  for(const bad of [null,undefined,'',9,1001,55.5,'abc'])assert.equal(accuracyLimit(bad),100);
});

const fakeClient=result=>({from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>result})})})});
test('schoolAccuracyLimit reads the school value and tolerates failures',async()=>{
  assert.equal(await schoolAccuracyLimit(fakeClient({data:{location_accuracy_m:1000}}),'s'),1000);
  assert.equal(await schoolAccuracyLimit(fakeClient({error:{message:'x'}}),'s'),100);
  assert.equal(await schoolAccuracyLimit({from(){throw new Error('x');}},'s'),100);
  assert.equal(await schoolAccuracyLimit(fakeClient({data:null}),''),100);
});

test('a 111 m reading passes with a 1 km tolerance',async()=>{
  const geo={watchPosition(ok){ok({coords:{latitude:45,longitude:9,accuracy:111},timestamp:Date.now()});return 1;},clearWatch(){}};
  const p=await accuratePosition({geolocation:geo,maxAccuracy:1000,timeoutMs:50});
  assert.equal(p.coords.accuracy,111);
  await assert.rejects(accuratePosition({geolocation:geo,timeoutMs:20}),/entro 100 m/);
});

test('migration makes both confirmations use the school tolerance',()=>{
  const sql=readFileSync(new URL('../../supabase/migrations/20261109020000_school_location_accuracy.sql',import.meta.url),'utf8');
  assert.match(sql,/check \(location_accuracy_m between 10 and 1000\)/);
  assert.match(sql,/set location_accuracy_m=1000 where is_demo/);
  assert.match(sql,/'aal'\)<>'aal2'/);
  assert.match(sql,/p_accuracy_m > v_school\.location_accuracy_m/);
  assert.match(sql,/p_accuracy_m>v_school\.location_accuracy_m/);
});
