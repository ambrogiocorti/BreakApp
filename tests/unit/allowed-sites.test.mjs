import test from 'node:test';
import assert from 'node:assert/strict';
import {DEFAULT_SITE_URL,resolveAllowedSite,corsHeaders} from '../../supabase/functions/_shared/allowed-sites.mjs';

test('default site keeps the existing GitHub Pages origin and return path',()=>{
 const site=resolveAllowedSite('https://ambrogiocorti.github.io',undefined);
 assert.equal(site.baseUrl,DEFAULT_SITE_URL);
 assert.equal(site.origin,'https://ambrogiocorti.github.io');
 assert.equal(resolveAllowedSite('https://attacker.example',undefined),null);
});

test('only exact configured HTTPS origins map to their own configured base paths',()=>{
 const sites='https://ambrogiocorti.github.io/BreakApp/, https://demo.example/preview';
 assert.equal(resolveAllowedSite('https://demo.example',sites).baseUrl,'https://demo.example/preview/');
 assert.equal(resolveAllowedSite('https://ambrogiocorti.github.io',sites).baseUrl,DEFAULT_SITE_URL);
 for(const origin of ['https://demo.example.attacker.test','https://other.example','null','http://demo.example',null])
  assert.equal(resolveAllowedSite(origin,sites),null);
 const headers=corsHeaders(resolveAllowedSite('https://demo.example',sites),'POST, OPTIONS');
 assert.equal(headers['access-control-allow-origin'],'https://demo.example');
 assert.equal(headers.vary,'Origin');
 assert.equal(corsHeaders(null,'POST, OPTIONS')['access-control-allow-origin'],undefined);
});

test('invalid or ambiguous server configuration fails closed',()=>{
 for(const sites of [
  'http://demo.example/',
  'https://user:password@demo.example/',
  'https://demo.example/?return=evil',
  'https://demo.example/#fragment',
  'https://*.example/',
  'https://demo.example/one/,https://demo.example/two/',
  'https://demo.example/,not a URL',
  'https://demo.example/,'
 ])assert.equal(resolveAllowedSite('https://demo.example',sites),null,sites);
});
