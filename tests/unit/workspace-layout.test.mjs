import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const css=readFileSync(new URL('../../src/css/base.css',import.meta.url),'utf8');
const shell=readFileSync(new URL('../../src/js/features/shell/workspace.js',import.meta.url),'utf8');

test('desktop has fixed full-height sidebar with independent routed content',()=>{
 assert.match(html,/id="workspace-sidebar"/);
 assert.match(html,/id="workspace-page-head"/);
 assert.match(css,/\.workspace-sidebar\{display:flex!important;position:fixed/);
 assert.match(css,/\.app-main\{position:fixed;top:166px;bottom:0/);
 assert.match(css,/section:not\(\.is-route-active\)\{/);
});
test('role navigation is generated; no static student-only nav remains',()=>{
 assert.match(html,/id="app-desktop-nav"[^>]*><\/nav>/);
 assert.match(html,/id="app-mobile-nav"[^>]*><\/nav>/);
 assert.match(shell,/contextsFromMemberships/);
 assert.match(shell,/allowedRoute/);
});
test('profile includes mobile role switch and all app views are preserved',()=>{
 assert.match(html,/id="workspace-profile-context-select"/);
 assert.match(shell,/profileSelect.addEventListener/);
 for(const id of ['accesso','menu','orders','staff-orders-section',
 'warehouse-inventory','admin-overview','admin-catalog','admin-order-setup',
 'bar-operations','support-center','platform-overview']){
   assert.ok(html.includes('id="'+id+'"'),'missing '+id);
 }
});
test('dashboard and inventory are distinct real feature modules',()=>{
 const dash=readFileSync(new URL('../../src/js/features/shell/dashboards.js',import.meta.url),'utf8');
 const inventory=readFileSync(new URL('../../src/js/features/warehouse/inventory.js',import.meta.url),'utf8');
 assert.match(dash,/client\.from\('orders'\)/);
 assert.match(inventory,/client\.from\('daily_stock'\)/);
 assert.match(inventory,/\.select\('id'\)\.single\(\)/);
});
