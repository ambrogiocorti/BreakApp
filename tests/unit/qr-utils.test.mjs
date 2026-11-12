import test from 'node:test';
import assert from 'node:assert/strict';
import { makePickupQrValue,parsePickupQrValue,parseOrderDisplayNumber } from '../../src/js/features/orders/qr-utils.js';
const id='11111111-1111-4111-8111-111111111111';
test('QR roundtrip contains only unguessable UUID token',()=>{
 const value=makePickupQrValue(id);assert.equal(parsePickupQrValue(value),id);
 assert.equal(parsePickupQrValue(value+'-extra'),null);
});
test('scanner rejects links, nonsense and broken tokens',()=>{
 for(const v of ['https://evil.example/a','breakapp:pickup:','breakapp:pickup:123','11111111-1111-4111-8111-111111111111'])
   assert.equal(parsePickupQrValue(v),null);
});
test('manual search accepts only positive decimal order numbers',()=>{
 assert.equal(parseOrderDisplayNumber('123'),'123');
 for(const v of ['0','-1','1.5','foo','01','1 OR 1=1','999999999999999999999999'])
   assert.equal(parseOrderDisplayNumber(v),null);
});
