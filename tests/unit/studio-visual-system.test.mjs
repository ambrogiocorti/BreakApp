import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const root=new URL('../../',import.meta.url);
const page=readFileSync(new URL('index.html',root),'utf8');
const main=readFileSync(new URL('src/js/main.js',root),'utf8');
const v3=readFileSync(new URL('src/css/service-desk.css',root),'utf8');
const shell=readFileSync(new URL('src/js/features/shell/workspace.js',root),'utf8');
const platform=readFileSync(new URL('src/js/features/shell/platform-dashboard.js',root),'utf8');

test('Edition 03 is a structural app redesign, loaded after existing component styles',()=>{
 assert.ok(main.indexOf("import '../css/service-desk.css';")>main.indexOf("import '../css/studio.css';"));
 assert.match(main,/initializeOrders\(client\)/);
 assert.match(main,/initializeWorkspace\(client\)/);
 assert.match(main,/initializeWorkspaceDashboards\(client\)/);
});
test('real flows retain their DOM hooks and every role route',()=>{
 for(const id of [
  'workspace-sidebar','workspace-context-select','app-desktop-nav','app-mobile-nav',
  'workspace-page-head','workspace-account','workspace-index','workspace-index-nav',
  'notifications-toggle','auth-form','google-button','microsoft-button','admin-mfa',
  'platform-overview','admin-overview','platform-schools','staff-orders-section',
  'menu-grid','menu-categories','menu-school','order-submit','staff-refund-submit','platform-refresh',
  'platform-metrics','dashboard-metrics','platform-school-list','dashboard-order-status',
  'menu-refresh','menu-bar','menu-search','school-access-status'
 ])assert.match(page,new RegExp('id="'+id+'"'),'missing application hook: '+id);
 assert.match(shell,/allowedRoute\(active\.role,requested\)/);
 assert.match(shell,/const indexNav=document\.getElementById\('workspace-index-nav'\)/);
 assert.match(shell,/SCREENS\[active\?\.role\]/);
});
test('dashboards no longer use identical four-card grids under decorative banners',()=>{
 assert.equal((page.match(/class="overview-intro"/g)||[]).length,0);
 assert.equal((page.match(/class="control-heading"/g)||[]).length,1);
 assert.equal((page.match(/class="control-heading control-heading-platform"/g)||[]).length,1);
 assert.equal((page.match(/class="control-layout"/g)||[]).length,1);
 assert.equal((page.match(/class="control-layout control-layout-platform"/g)||[]).length,1);
 assert.match(page,/id="platform-school-list" class="platform-school-roster"/);
});
test('school network is a real-data roster and progress rail, not an SVG donut',()=>{
 assert.match(platform,/function roster\(rows\)/);
 assert.match(platform,/network-meter-fill/);
 assert.doesNotMatch(platform,/document\.createElementNS/);
 assert.match(platform,/aria-valuenow/);
});
test('customer marketplace has a true filter rail and browsing feed',()=>{
 assert.match(page,/class="market-workbench"/);
 assert.match(page,/class="market-sidebar"/);
 assert.match(page,/class="market-results"/);
 assert.match(page,/id="menu-categories"/);
 assert.match(page,/id="menu-grid"/);
 assert.match(v3,/\.market-sidebar \.menu-category-chip/);
});
test('keyboard navigation, dark mode, mobile dock and reduced motion',()=>{
 assert.match(v3,/#workspace-index:not\(\[open\]\) #workspace-index-nav\{display:none;/);
 assert.match(v3,/:root\[data-theme="dark"\]/);
 assert.match(v3,/\.app-mobile-nav/);
 assert.match(v3,/:focus-visible/);
 assert.match(v3,/prefers-reduced-motion/);
 assert.match(v3,/@media\(max-width:460px\)/);
 assert.doesNotMatch(v3,/@import|fonts\.googleapis\.com/);
 assert.doesNotMatch(v3,/sk_(test|live)_|service_role/);
});
