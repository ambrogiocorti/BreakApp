import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';

const root=new URL('../../',import.meta.url);
const read=path=>readFileSync(new URL(path,root),'utf8');
const page=read('index.html');
const main=read('src/js/main.js');
const shell=read('src/js/features/shell/workspace.js');
const platform=read('src/js/features/shell/platform-dashboard.js');
const cssFiles=readdirSync(new URL('src/css/',root)).filter(f=>f.endsWith('.css'));
const css=Object.fromEntries(cssFiles.map(f=>[f,read('src/css/'+f)]));
const allCss=Object.values(css).join('\n');

test('one stylesheet entry, imported once by the application',()=>{
 assert.match(main,/^import '\.\.\/css\/app\.css';/m);
 assert.equal((main.match(/import '\.\.\/css\//g)||[]).length,1);
 for(const file of ['tokens.css','base.css','components.css','shell.css'])
  assert.match(css['app.css'],new RegExp("@import './"+file.replace('.','\\.')+"';"));
 assert.match(main,/initializeOrders\(client\)/);
 assert.match(main,/initializeWorkspace\(client,\{prepareRole:/);
 assert.match(read('src/js/staff-modules.js'),/initializeWorkspaceDashboards\(client\)/);
});
test('fonts are self-hosted packages: no external font or script hosts (CSP style-src self)',()=>{
 assert.doesNotMatch(allCss+page,/fonts\.googleapis\.com|fonts\.gstatic\.com|cdn\.jsdelivr|unpkg\.com/);
 assert.match(css['tokens.css'],/@fontsource-variable\/bricolage-grotesque/);
 assert.match(css['tokens.css'],/@fontsource-variable\/atkinson-hyperlegible-next/);
 assert.doesNotMatch(allCss,/sk_(test|live)_|service_role/);
});
test('real flows retain their DOM hooks and every role route',()=>{
 for(const id of [
  'workspace-sidebar','workspace-context-select','app-desktop-nav','app-mobile-nav',
  'workspace-page-head','workspace-account','workspace-scrim','workspace-drawer-close',
  'notifications-toggle','auth-form','google-button','microsoft-button','admin-mfa',
  'platform-overview','admin-overview','platform-schools','staff-orders-section',
  'menu-grid','menu-categories','menu-school','order-submit','staff-refund-submit','platform-refresh',
  'platform-metrics','dashboard-metrics','platform-school-list','dashboard-order-status',
  'menu-refresh','menu-bar','menu-search','school-access-status','app-confirm-dialog','theme-choice'
 ])assert.match(page,new RegExp('id="'+id+'"'),'missing application hook: '+id);
 assert.match(shell,/allowedRoute\(active\.role,requested\)/);
 assert.match(shell,/SCREENS\[active\?\.role\]/);
});
test('navigation: grouped sidebar, short phone tab bar, «Altro» opens the drawer',()=>{
 assert.match(shell,/const MOBILE_PRIMARY=/);
 assert.match(shell,/nav-group-label/);
 assert.match(shell,/openDrawer\(\)/);
 assert.match(shell,/event\.key==='Escape'/);
 assert.match(shell,/\['staff-orders-section','Banco'/);
 for(const [role,list] of Object.entries({customer:4,bartender:3,warehouse_manager:2,school_admin:3,platform_admin:3})){
  const block=shell.slice(shell.indexOf('const MOBILE_PRIMARY='));
  const match=block.match(new RegExp(role+":\\[([^\\]]*)\\]"));
  assert.ok(match,'missing tab bar for '+role);
  assert.ok(match[1].split(',').length<=list,'too many tabs for '+role);
 }
 assert.doesNotMatch(page,/workspace-index/);
});
test('one visible page title: sections do not repeat decorative headings',()=>{
 assert.equal((page.match(/<h1\b/g)||[]).length,2,'login heading + workspace page title');
 for(const phrase of ['Il banco, sotto controllo','Una rete. Tante scuole.','overview-intro','control-heading'])
  assert.ok(!page.includes(phrase),'decorative heading left: '+phrase);
});
test('school network is a real-data roster and progress rail, not an SVG donut',()=>{
 assert.match(platform,/function roster\(rows\)/);
 assert.match(platform,/network-meter-fill/);
 assert.doesNotMatch(platform,/document\.createElementNS/);
 assert.match(platform,/aria-valuenow/);
});
test('customer marketplace keeps the filter rail and browsing feed',()=>{
 for(const cls of ['market-workbench','market-sidebar','market-results'])assert.match(page,new RegExp('class="'+cls+'"'));
 assert.match(css['customer.css'],/\.market-sidebar \.menu-category-chip/);
 assert.match(css['customer.css'],/position: sticky/);
});
test('themes, focus, reduced motion, touch targets and phone layouts',()=>{
 assert.match(css['tokens.css'],/:root\[data-theme="dark"\]/);
 assert.match(css['tokens.css'],/--control-h: 44px/);
 assert.match(css['base.css'],/:focus-visible/);
 assert.match(css['base.css'],/prefers-reduced-motion/);
 assert.match(css['shell.css'],/\.app-mobile-nav/);
 assert.match(css['shell.css'],/@media \(min-width: 1024px\)/);
 assert.match(css['base.css'],/font-size: var\(--text-base\)/,'inputs at 16 px avoid iOS zoom');
 assert.doesNotMatch(allCss,/backdrop-filter:\s*blur/,'no glassmorphism');
 assert.doesNotMatch(allCss,/font-size:\s*(?:[0-9](?:\.\d+)?|1[01])px/,'no text below 12 px');
});
test('native confirm and prompt are replaced by the shared dialog',()=>{
 for(const dir of ['auth','catalog','groups','menu','notifications','offline','operations','orders','shell','support','warehouse']){
  for(const file of readdirSync(new URL('src/js/features/'+dir+'/',root)).filter(f=>f.endsWith('.js'))){
   const source=read('src/js/features/'+dir+'/'+file);
   assert.doesNotMatch(source,/(?<![\w.$])(?:window\.)?(?:confirm|prompt)\(/,dir+'/'+file);
  }
 }
});
