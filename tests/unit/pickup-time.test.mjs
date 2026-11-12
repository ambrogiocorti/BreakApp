import test from 'node:test';
import assert from 'node:assert/strict';
import {romeToday,isUpcomingWindow} from '../../src/js/core/pickup-time.js';

// 22:40 UTC on 8 November = 23:40 in Rome (CET).
const now=new Date('2026-11-08T22:40:00Z');

test('today is computed in the school time zone, not UTC',()=>{
 assert.equal(romeToday(new Date('2026-11-08T23:30:00Z')),'2026-11-09');
 assert.equal(romeToday(now),'2026-11-08');
});

test('windows of previous days are never selectable',()=>{
 assert.equal(isUpcomingWindow({service_date:'2026-11-07',starts_at:'23:59:00'},now),false);
 assert.equal(isUpcomingWindow({service_date:'2026-11-05',starts_at:'10:00:00'},now),false);
});

test('a window of today is selectable only until it starts',()=>{
 assert.equal(isUpcomingWindow({service_date:'2026-11-08',starts_at:'23:30:00'},now),false);
 assert.equal(isUpcomingWindow({service_date:'2026-11-08',starts_at:'23:40:00'},now),false);
 assert.equal(isUpcomingWindow({service_date:'2026-11-08',starts_at:'23:45'},now),true);
 assert.equal(isUpcomingWindow({service_date:'2026-11-09',starts_at:'10:00:00'},now),true);
});

test('incomplete windows are not selectable',()=>{
 assert.equal(isUpcomingWindow(null,now),false);
 assert.equal(isUpcomingWindow({service_date:'2026-11-09'},now),false);
});

test('every customer and staff slot picker filters past windows',async()=>{
 const {readFile}=await import('node:fs/promises');
 for(const file of ['orders/orders.js','groups/groups.js','operations/workflows.js','operations/completion-ui.js']){
  const src=await readFile(new URL('../../src/js/features/'+file,import.meta.url),'utf8');
  assert.match(src,/isUpcomingWindow/,file+' does not filter past windows');
 }
});
