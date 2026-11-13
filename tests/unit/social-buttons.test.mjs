import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('Google and Microsoft stay enabled unless the server says they are off',()=>{
  const src=readFileSync(new URL('../../src/js/features/auth/auth.js',import.meta.url),'utf8');
  assert.match(src,/google\.disabled=busy\|\|oauthProviders\?\.google===false/);
  assert.match(src,/microsoft\.disabled=busy\|\|oauthProviders\?\.azure===false/);
  assert.doesNotMatch(src,/Non è possibile verificare gli accessi esterni/);
});
