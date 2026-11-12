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

test('GitHub Pages build carries a Content-Security-Policy meta tag limited to the Supabase origin',async()=>{
 const {contentSecurityPolicy,contentSecurityPolicyPlugin}=await import('../../scripts/content-security-policy.mjs');
 const policy=contentSecurityPolicy('https://ynvswdyirngvdpudcikl.supabase.co');
 for(const directive of ["default-src 'self'","script-src 'self'","style-src 'self'","object-src 'none'","base-uri 'self'","form-action 'self'"])
  assert.ok(policy.includes(directive),directive);
 assert.match(policy,/connect-src 'self' https:\/\/ynvswdyirngvdpudcikl\.supabase\.co wss:\/\/ynvswdyirngvdpudcikl\.supabase\.co/);
 assert.doesNotMatch(policy,/unsafe-inline|unsafe-eval|\*/);
 assert.equal(contentSecurityPolicy('').includes('supabase'),false);
 const html=contentSecurityPolicyPlugin({VITE_SUPABASE_URL:'https://x.supabase.co'}).transformIndexHtml('<head>\n    <meta charset="UTF-8" />\n<script type="module" src="/a.js"></script></head>');
 assert.ok(html.indexOf('Content-Security-Policy')<html.indexOf('<script'),'CSP must precede scripts');
});
