import test from 'node:test';
import assert from 'node:assert/strict';
import { filterPublicMenu, barsForSchool } from '../../src/js/features/menu/utils.js';

const categories = [
  { id: 'a', name:'Panini', is_active:true },
  { id: 'b', name:'Riservati', is_active:false }
];
const products = [
  { id:'1', name:'Panino al tonno', description:'Tonno e pomodoro', category_id:'a', is_active:true },
  { id:'2', name:'Focaccia', description:'', category_id:'a', is_active:false },
  { id:'3', name:'Prodotto segreto', description:'', category_id:'b', is_active:true }
];
test('il menu nasconde prodotti e categorie disattivati', () => {
  assert.deepEqual(filterPublicMenu(categories, products).map((p) => p.id), ['1']);
});
test('ricerca e categorie filtrano senza esporre nascosti', () => {
  assert.deepEqual(filterPublicMenu(categories, products, { search:'TONNO', categoryId:'a' }).map((p) => p.id), ['1']);
  assert.deepEqual(filterPublicMenu(categories, products, { search:'segreto' }), []);
  assert.deepEqual(filterPublicMenu(categories, products, { categoryId:'b' }), []);
});
test('bar di scuole diverse restano separati', () => {
  const bars = [
    { id:'x', school_id:'s1', is_active:true },
    { id:'y', school_id:'s2', is_active:true },
    { id:'z', school_id:'s1', is_active:false }
  ];
  assert.deepEqual(barsForSchool(bars, 's1').map((bar) => bar.id), ['x']);
});
