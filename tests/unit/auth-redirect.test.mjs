import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { authRedirectUrl } from '../../src/js/features/auth/redirect.js';

test('Supabase Auth callbacks return to the published GitHub Pages project path', () => {
  assert.equal(
    authRedirectUrl('https://ambrogiocorti.github.io', '/BreakApp/'),
    'https://ambrogiocorti.github.io/BreakApp/'
  );
  assert.equal(authRedirectUrl('https://breakapp.example', '/'), 'https://breakapp.example/');
  assert.equal(authRedirectUrl('http://localhost:5173', '/BreakApp/'), 'http://localhost:5173/BreakApp/');
});

test('a crafted base path cannot change the callback origin', () => {
  assert.throws(() => authRedirectUrl('https://ambrogiocorti.github.io', '//evil.example/'));
  assert.throws(() => authRedirectUrl('https://ambrogiocorti.github.io', '/BreakApp/../'));
  assert.throws(() => authRedirectUrl('http://evil.example', '/BreakApp/'));
});

test('email verification and OAuth use the same deployment-aware callback', () => {
  const auth = readFileSync(new URL('../../src/js/features/auth/auth.js', import.meta.url), 'utf8');
  const occurrences=auth.match(/authRedirectUrl\(window\.location\.origin, import\.meta\.env\.BASE_URL\)/g)||[];
  assert.equal(occurrences.length,2);
  assert.doesNotMatch(auth,/window\.location\.origin\s*\+\s*['"]\/['"]/);
});
