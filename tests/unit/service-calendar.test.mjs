import test from 'node:test';
import assert from 'node:assert/strict';
import { parseWeeklyPeriods, isWindowBlocked, formatWeeklyPeriods } from '../../src/js/features/operations/calendar-core.js';

test('planner supports multiple non-overlapping time intervals',()=>{
 const p=parseWeeklyPeriods('10:30-13:00\n08:00-10:00');
 assert.equal(p[0].starts_at,'08:00');
 assert.equal(formatWeeklyPeriods(p),'08:00–10:00, 10:30–13:00');
 assert.deepEqual(parseWeeklyPeriods(''),[]);
});
test('planner rejects invalid hours and overlaps',()=>{
 for(const value of ['25:00-26:00','10:00-09:00','08:00-10:00\n09:00-11:00','not a time'])
   assert.throws(()=>parseWeeklyPeriods(value));
});
test('closures only block overlapping slots on same date and not reopened closures',()=>{
 const slot={service_date:'2026-11-03',starts_at:'10:30:00',ends_at:'10:50:00'};
 assert.equal(isWindowBlocked(slot,[{service_date:'2026-11-03',starts_at:'10:00:00',ends_at:'11:00:00',reopened_at:null}]),true);
 assert.equal(isWindowBlocked(slot,[{service_date:'2026-11-04',starts_at:'10:00:00',ends_at:'11:00:00',reopened_at:null}]),false);
 assert.equal(isWindowBlocked(slot,[{service_date:'2026-11-03',starts_at:'10:00:00',ends_at:'11:00:00',reopened_at:'2026-11-01T12:00:00Z'}]),false);
});
