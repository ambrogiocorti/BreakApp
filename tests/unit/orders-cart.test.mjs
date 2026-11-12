import test from 'node:test';
import assert from 'node:assert/strict';
import { cartAdd, cartSetQuantity, cartSummary, safeCartParse, toRpcItems } from '../../src/js/features/orders/cart-core.js';
const a='11111111-1111-4111-8111-111111111111', b='22222222-2222-4222-8222-222222222222';
const products=[{ id:a, name:'Panino', price_cents:250, is_active:true },{id:b,name:'Acqua',price_cents:100,is_active:true}];
test('il carrello somma e non moltiplica per centesimi floating point',()=>{
 const x=cartAdd(cartAdd([],a,2),b,3);
 assert.deepEqual(cartSummary(x,products).totalCents,800);
 assert.deepEqual(toRpcItems(x),x);
});
test('quantita non negative, rimozione e limite per singolo prodotto',()=>{
 assert.equal(cartSetQuantity([{product_id:a,quantity:1}],a,0).length,0);
 assert.throws(()=>cartAdd([{product_id:a,quantity:999}],a,2));
 assert.throws(()=>cartSetQuantity([],a,-1));
});
test('un carrello di un bar diverso non viene importato',()=>{
 const s=JSON.stringify({bar_id:a,items:[{product_id:b,quantity:1}]});
 assert.equal(safeCartParse(s,b).length,0);
 assert.equal(safeCartParse(s,a).length,1);
});
test('un prezzo non valido o prodotto disattivato blocca checkout',()=>{
 assert.throws(()=>cartSummary([{product_id:a,quantity:1}],[{...products[0],is_active:false}]));
 assert.throws(()=>cartSummary([{product_id:b,quantity:1}],products.slice(0,1)));
});
