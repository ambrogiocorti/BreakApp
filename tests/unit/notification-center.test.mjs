import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {noticeCategory,noticeTime} from '../../src/js/features/notifications/notifications.js';

test('notifications show a clear category and a human readable date',()=>{
 assert.equal(noticeCategory('group_join_requested').label,'Gruppo');
 assert.equal(noticeCategory('refund_issue').label,'Rimborso');
 assert.equal(noticeCategory('support_reply').label,'Assistenza');
 assert.equal(noticeCategory('school_announcement').label,'Avviso scuola');
 assert.equal(noticeCategory('cash_anomaly').label,'Avviso scuola');
 assert.equal(noticeCategory('order_status').label,'Ordine');
 assert.equal(noticeTime('invalid'),'Data non disponibile');
 assert.match(noticeTime('2026-11-09T12:36:01Z',new Date('2026-11-09T15:00:00Z')),/Oggi/);
});

test('notification inbox has accessible actions and push device status',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
 assert.match(html,/id="notifications-mark-all"/);
 assert.match(html,/id="notifications-device-state"[^>]*role="status"/);
 const controller=readFileSync(new URL('../../src/js/features/notifications/notifications.js',import.meta.url),'utf8');
 assert.match(controller,/if\('serviceWorker' in navigator\)\{/);
 const worker=readFileSync(new URL('../../public/sw.js',import.meta.url),'utf8');
 assert.match(worker,/targetClient=typeof open\.navigate/);
 const dispatcher=readFileSync(new URL('../../supabase/functions/push-dispatch/index.ts',import.meta.url),'utf8');
 assert.match(dispatcher,/notificationSummary\(job\)/);
 assert.match(dispatcher,/tag:'breakapp-notice-'/);
});
