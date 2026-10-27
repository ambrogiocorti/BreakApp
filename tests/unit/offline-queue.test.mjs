import test from 'node:test';
import assert from 'node:assert/strict';
import {indexedDB} from 'fake-indexeddb';
import {openOfflineDB,saveDevice,appendPending,readPending,readDevice} from '../../src/js/features/offline/vault.js';
globalThis.indexedDB=indexedDB;
test('concurrent offline writes commit in causal order and a stale save cannot reset the sequence',async()=>{
 const db=await openOfflineDB(),device={context:'causal-order',deviceId:'test-device',generation:1};
 await saveDevice(db,device);
 await Promise.all(Array.from({length:20},(_,i)=>appendPending(db,{...device},{
  id:'causal-'+i,context:device.context,createdAt:'2026-10-27T10:00:00Z',encrypted:{sealed:[i]}
 })));
 const entries=await readPending(db,device.context);
 assert.deepEqual(entries.map(x=>x.sequence),Array.from({length:20},(_,i)=>i+1));
 await saveDevice(db,{...device,nextSequence:0});
 assert.equal((await readDevice(db,device.context)).nextSequence,20);db.close();
});
test('a device generation changed in another tab cannot append to the old queue',async()=>{
 const db=await openOfflineDB(),old={context:'transfer-race',deviceId:'old-device',generation:1};
 await saveDevice(db,old);
 await saveDevice(db,{...old,deviceId:'new-device',generation:2});
 await assert.rejects(()=>appendPending(db,old,{id:'refused',context:old.context,
  createdAt:'2026-10-27T10:00:00Z',encrypted:{sealed:[1]}}));
 assert.equal((await readPending(db,old.context)).length,0);db.close();
});
