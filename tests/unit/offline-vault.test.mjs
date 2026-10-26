import test from 'node:test';
import assert from 'node:assert/strict';
import { validateOfflinePin,pinSalt,deriveOfflineKey,sealOffline,unsealOffline }
 from '../../src/js/features/offline/vault.js';
import { allowedRoute } from '../../src/js/features/shell/workspace.js';

test('PIN is at least six numeric digits and never stored in plaintext',()=>{
 for(const pin of ['123','abc123','123 456','1234567890123',''])assert.equal(validateOfflinePin(pin),false);
 assert.equal(validateOfflinePin('123456'),true);
 assert.equal(validateOfflinePin('123456789012'),true);
});
test('AES-GCM offline event is encrypted and PIN mismatch rejects decryption',async()=>{
 const salt=pinSalt();
 const key=await deriveOfflineKey('384729',salt);
 const event={kind:'counter_sale',amount_cents:260,note:'Cassa banco',request_key:'unit-test'};
 const envelope=await sealOffline(key,event);
 assert.equal(envelope.iv.length,12);
 assert.equal(JSON.stringify(envelope).includes('Cassa banco'),false);
 assert.deepEqual(await unsealOffline(key,envelope),event);
 const other=await deriveOfflineKey('999999',salt);
 await assert.rejects(()=>unsealOffline(other,envelope));
});
test('corrupted ciphertext and IV are rejected, not silently repaired',async()=>{
 const key=await deriveOfflineKey('123456',pinSalt());
 const envelope=await sealOffline(key,{amount_cents:190});
 envelope.sealed[2]^=1;
 await assert.rejects(()=>unsealOffline(key,envelope));
 await assert.rejects(()=>unsealOffline(key,{iv:[1,2],sealed:[1,2,3]}));
});
test('only bartender route exposes offline queue, never global administrator',()=>{
 assert.equal(allowedRoute('bartender','offline-terminal'),true);
 for(const role of ['customer','warehouse_manager','school_admin','platform_admin'])
  assert.equal(allowedRoute(role,'offline-terminal'),false);
});
