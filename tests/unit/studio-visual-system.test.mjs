import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const page = readFileSync(new URL('index.html', root), 'utf8');
const main = readFileSync(new URL('src/js/main.js', root), 'utf8');
const studio = readFileSync(new URL('src/css/studio.css', root), 'utf8');

test('Studio 02 CSS is loaded after legacy component styles, preserving business JS', () => {
  const old = main.indexOf("import '../css/groups.css';");
  const next = main.indexOf("import '../css/studio.css';");
  assert.ok(old > 0 && next > old);
  assert.match(main, /initializeWorkspace\(client\)/);
  assert.match(main, /initializeOrders\(client\)/);
  assert.match(main, /initializeWorkspaceDashboards\(client\)/);
});

test('role-bound shell selectors and server-bound forms remain present', () => {
  for (const id of [
    'workspace-sidebar','workspace-context-select','app-desktop-nav','app-mobile-nav',
    'workspace-page-head','workspace-account','notifications-toggle',
    'auth-form','google-button','microsoft-button','admin-mfa',
    'platform-overview','admin-overview','platform-schools','staff-orders-section',
    'menu-grid','order-submit','staff-refund-submit','platform-refresh',
  ]) {
    assert.match(page, new RegExp('id="' + id + '"'), 'missing shell binding: ' + id);
  }
  assert.equal((page.match(/class="overview-intro"/g) || []).length, 2);
  assert.match(page, /href="#platform-schools"/);
  assert.match(page, /href="#staff-orders-section"/);
});

test('Studio 02 covers every role, mobile navigation, dark mode, reduced motion and keyboard focus', () => {
  assert.match(studio, /:root\[data-theme="dark"\]/);
  assert.match(studio, /body\[data-workspace="true"\] \.workspace-sidebar/);
  assert.match(studio, /\.app-mobile-nav/);
  assert.match(studio, /\.menu-product-card/);
  assert.match(studio, /\.staff-board/);
  assert.match(studio, /\.overview-intro/);
  assert.match(studio, /:focus-visible/);
  assert.match(studio, /prefers-reduced-motion/);
  assert.match(studio, /@media\(max-width:550px\)/);
  assert.doesNotMatch(studio, /@import|fonts\.googleapis\.com/);
  assert.doesNotMatch(studio, /sk_(test|live)_|service_role/);
});

test('design does not fabricate financial KPIs or alter role-based navigation identifiers', () => {
  const banner = [...page.matchAll(/<div class="overview-intro">([\s\S]*?)<\/div>\s*<div class="dashboard-toolbar">/g)];
  assert.equal(banner.length, 2);
  assert.equal(page.includes('class="workspace-sidebar"'), true);
  assert.match(page, /id="dashboard-metrics"/);
  assert.match(page, /id="platform-metrics"/);
  assert.doesNotMatch(banner.map(m => m[1]).join(''), /€\s*\d|\d+\s*(ordini|scuole|incassi)/);
});
