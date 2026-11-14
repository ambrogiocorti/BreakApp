import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {isRoutineNotice,usefulNotices} from '../../src/js/features/notifications/routine-notices.js';

const row=message=>({event_type:'order_status',message});

test('routine order notices are hidden, useful ones stay',()=>{
 for(const m of [
  'Ordine #20: stato aggiornato a delivered.',
  'Ordine #19: stato aggiornato a ready.',
  'Ordine confermato. Controlla in app la fascia di ritiro e il saldo.',
  'Rimborso richiesto: importi online in elaborazione ai pagatori originali; eventuali contanti devono essere restituiti fisicamente.',
  'Pagamento con carta annullato al banco: hai pagato direttamente al bar.'
 ])assert.equal(isRoutineNotice(row(m)),true,m);
 for(const m of [
  'Ordine annullato: chiusura straordinaria. Eventuali rimborsi sono in elaborazione verso i pagatori originali.',
  'Non hai ritirato in tempo: il tuo ordine è passato alla fascia 11:40.',
  'Rimborso amministrativo richiesto: importi online in elaborazione.'
 ])assert.equal(isRoutineNotice(row(m)),false,m);
 assert.equal(isRoutineNotice({event_type:'group_confirmed',message:'Ordine confermato. Controlla in app'}),false);
 assert.deepEqual(usefulNotices([row('Ordine #1: stato aggiornato a ready.'),{event_type:'support_reply',message:'x'}]).length,1);
});

test('database stops creating routine notices',()=>{
 const sql=readFileSync(new URL('../../supabase/migrations/20261114120000_quiet_routine_notices.sql',import.meta.url),'utf8');
 assert.match(sql,/drop trigger if exists orders_notify_state on public\.orders/);
 assert.match(sql,/drop trigger if exists individual_booking_notice on public\.orders/);
 assert.match(sql,/'Rimborso richiesto:%'/);
 assert.match(sql,/'Pagamento con carta annullato al banco%'/);
 const orders=readFileSync(new URL('../../src/js/features/orders/orders.js',import.meta.url),'utf8');
 assert.match(orders,/usefulNotices\(n\.data\)/);
});
