import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fiscalSummary,fiscalTable,fiscalLinesText,fiscalTypeLabel} from '../../src/js/features/shell/fiscal-documents.js';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const docs=[
  {created_at:'2026-11-12T10:00:00Z',reference:'#5',doc_type:'sale',payment_method:'cash',amount_cents:500,order_total_cents:500,
   lines:[{name:'Panino',quantity:2,unit_cents:250}],status:'to_issue'},
  {created_at:'2026-11-12T11:00:00Z',reference:'#5',doc_type:'return',payment_method:'cash',amount_cents:500,order_total_cents:500,lines:[],status:'to_issue'},
  {created_at:'2026-11-12T12:00:00Z',reference:'#6',doc_type:'sale',payment_method:'card',amount_cents:250,order_total_cents:250,lines:[],status:'issued'}];
test('summary counts only receipts still to issue',()=>{
  assert.deepEqual(fiscalSummary(docs),{count:2,sales_cents:500,returns_cents:500});
});
test('labels and product lines are readable',()=>{
  assert.equal(fiscalLinesText(docs[0].lines),'2× Panino');
  assert.equal(fiscalTypeLabel(docs[1]),'Reso');
});
test('CSV export has one row per receipt with euro amounts',()=>{
  const t=fiscalTable(docs);
  assert.equal(t.length,4);
  assert.deepEqual(t[1].slice(1,5),['#5','Vendita','Contanti',5]);
  assert.equal(t[3][7],'Emesso');
});
test('UI uses the server RPCs and never reads the table directly',()=>{
  const js=read('src/js/features/shell/fiscal-documents.js');
  assert.match(js,/rpc\('list_fiscal_documents'/);
  assert.match(js,/rpc\('mark_fiscal_document'/);
  assert.doesNotMatch(js,/from\('fiscal_documents'\)/);
  assert.match(read('src/js/main.js'),/initializeFiscalDocuments\(client\)/);
  assert.match(read('index.html'),/id="fiscal-documents"/);
});
test('migration records sales and returns without exposing the table',()=>{
  const sql=read('supabase/migrations/20261112220000_fiscal_documents.sql');
  assert.match(sql,/revoke all on public\.fiscal_documents from public,anon,authenticated/);
  for(const t of ['payment_attempts','payment_refunds','counter_payments','group_counter_payments','order_additional_receipts','cash_refund_obligations'])
    assert.match(sql,new RegExp('on public\\.'+t));
  assert.match(sql,/on conflict \(source_key\) do nothing/);
});
