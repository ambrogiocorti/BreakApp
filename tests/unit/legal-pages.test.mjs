import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');

for(const page of ['public/privacy.html','public/termini.html']){
  test(`${page} is a standalone, script-free Italian page marked as draft`,()=>{
    const html=read(page);
    assert.match(html,/<html lang="it">/);
    assert.match(html,/<meta name="viewport"/);
    assert.match(html,/script-src 'none'/);
    assert.doesNotMatch(html,/<script/i);
    assert.match(html,/href="legal\.css"/);
    assert.match(html,/Bozza in attesa di revisione/);
    assert.match(html,/href="\.\/"/,'links back to the app with a base-relative URL');
    assert.doesNotMatch(html,/href="\//,'no root-absolute links: the site lives under /BreakApp/ on GitHub Pages');
  });
}

test('login, guest access and profile link to privacy and terms',()=>{
  const html=read('index.html');
  const login=html.slice(html.indexOf('id="login-panel"'),html.indexOf('id="signed-in-view"'));
  assert.match(login,/class="auth-legal"[^]*href="termini\.html"[^]*href="privacy\.html"/);
  const help=html.slice(html.indexOf('id="profile-help-title"'));
  assert.match(help,/href="privacy\.html"/);
  assert.match(help,/href="termini\.html"/);
  const guest=read('src/js/features/auth/guest.js');
  assert.match(guest,/legalLink\('termini\.html'/);
  assert.match(guest,/legalLink\('privacy\.html'/);
});

test('privacy notice states facts that match how the app works',()=>{
  const html=read('public/privacy.html');
  assert.match(html,/non viene salvata/,'position is checked at confirmation, not stored');
  assert.match(html,/Irlanda/,'Supabase project region eu-west-1');
  assert.match(html,/Stripe/);
  assert.match(html,/garanteprivacy\.it/);
});

test('service worker never caches standalone pages as the app shell',()=>{
  const sw=read('public/sw.js');
  assert.match(sw,/const isShell = url\.pathname === SHELL_URL/);
  assert.match(sw,/response\.ok && isShell/);
});

test('legal pages and profile give the support email',()=>{
  for(const f of ['public/privacy.html','public/termini.html','index.html'])
    assert.match(readFileSync(new URL('../../'+f,import.meta.url),'utf8'),/mailto:corti\.ambro@gmail\.com/);
});

test('privacy notice names the pilot bar as controller and the processor',()=>{
  const html=read('public/privacy.html');
  assert.match(html,/Phil Bar SNC/);
  assert.match(html,/Responsabile del trattamento:<\/strong> Ambrogio Corti/);
  assert.match(html,/2-quinquies/,'age of digital consent in Italy');
  assert.match(html,/Data Privacy Framework/);
});
