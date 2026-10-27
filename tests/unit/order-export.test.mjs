import test from 'node:test';
import assert from 'node:assert/strict';
import {ordersToCsv,exportSchoolOrdersCsv} from '../../src/js/features/shell/order-export.js';
test('CSV neutralizes spreadsheet formulas and escapes quotes',()=>{
 const csv=ordersToCsv([{display_no:'=HYPERLINK("evil")',created_at:'2026-10-27',status:'ready',payment_status:'due',total_cents:125}]);
 assert.match(csv,/"'=HYPERLINK\(""evil""\)"/);
});
test('export applies tenant filter and paginates',async()=>{
 const calls=[];
 const builder={select(){return this;},eq(field,id){calls.push([field,id]);return this;},order(){return this;},async range(){return {data:[{display_no:1}],error:null};}};
 const client={from:()=>builder};
 const r=await exportSchoolOrdersCsv(client,'11111111-1111-4111-8111-111111111111');
 assert.equal(r.count,1);assert.deepEqual(calls,[['school_id','11111111-1111-4111-8111-111111111111']]);
});
