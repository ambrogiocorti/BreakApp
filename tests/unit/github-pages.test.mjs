import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');

test('GitHub Pages emits relative asset and manifest paths under project base',()=>{
  const html=read('index.html');
  const vite=read('vite.config.js');
  const main=read('src/js/main.js');
  assert.match(html,/href="%BASE_URL%manifest\.webmanifest"/);
  assert.match(html,/href="%BASE_URL%icon-placeholder\.svg"/);
  assert.match(vite,/GITHUB_PAGES_BASE/);
  assert.match(main,/import\.meta\.env\.BASE_URL\}sw\.js/);
});
test('service worker caches only shell and static resources scoped to its script',()=>{
  const sw=read('public/sw.js');
  assert.match(sw,/new URL\('\.\/', self\.location\.href\)\.pathname/);
  assert.match(sw,/request\.method !== 'GET'/);
  assert.doesNotMatch(sw,/postMessage\(.*sale/);
});
test('GitHub Actions deploy requires Pages OIDC and main branch, not exposed secrets',()=>{
  const workflow=read('.github/workflows/github-pages.yml');
  assert.match(workflow,/pages: write/);
  assert.match(workflow,/id-token: write/);
  assert.match(workflow,/actions\/deploy-pages@v4/);
  assert.match(workflow,/actions\/upload-pages-artifact@v4/);
  assert.match(workflow,/branches: \[main\]/);
  assert.doesNotMatch(workflow,/service_role|sk_test_|sk_live_/);
});
