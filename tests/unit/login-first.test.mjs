import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
const auth = readFileSync(new URL('../../src/js/features/auth/auth.js', import.meta.url), 'utf8');
const mfa = readFileSync(new URL('../../src/js/features/auth/mfa.js', import.meta.url), 'utf8');

test('la radice presenta subito il login, non una homepage promozionale', () => {
  const main = html.slice(html.indexOf('<main '));
  const firstSection = main.match(/<section\b[^>]*>/)?.[0];
  assert.match(firstSection || '', /access-section/);
  assert.ok(html.includes('id="auth-form"'));
  assert.doesNotMatch(html, /class="hero container"|id="come-funziona"/);
});

test('il menu reale resta invisibile agli utenti non autenticati', () => {
  assert.match(html, /class="menu-section" id="menu" hidden/);
  assert.ok(auth.includes('menuSection.hidden = !present;'));
  assert.ok(auth.includes("document.body.dataset.authenticated = String(present);"));
});

test('workspace role-based: sidebar fissa, viste dedicate e bozze gruppo vere', () => {
  const shell = readFileSync(new URL('../../src/js/features/shell/workspace.js', import.meta.url), 'utf8');
  assert.ok(html.includes('id="app-mobile-nav"'));
  assert.ok(html.includes('id="app-desktop-nav"'));
  assert.ok(html.includes('id="workspace-sidebar"'));
  assert.ok(html.includes('id="workspace-context-select"'));
  assert.ok(html.includes('id="warehouse-inventory"'));
  assert.ok(html.includes('id="admin-overview"'));
  assert.ok(html.includes('id="orders"'));
  assert.ok(html.includes('id="order-stepper"'));
  assert.ok(shell.includes("['orders','I miei ordini'"));
  assert.ok(shell.includes("['warehouse-inventory','Scorte giornaliere'"));
  assert.ok(shell.includes("['groups','Gruppi'"));
});

test('il nuovo QR TOTP non scavalca il fattore gia verificato', () => {
  assert.ok(html.includes('id="mfa-lost-panel"'));
  assert.ok(mfa.includes("currentLevel === 'aal2' && totp"));
  assert.ok(mfa.includes("factors.data.totp?.some((item) => item.status === 'verified')"));
  assert.ok(mfa.includes("Il fattore esistente deve essere rimosso"));
  assert.ok(mfa.includes("client.auth.mfa.enroll"));
});
