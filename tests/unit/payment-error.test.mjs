import test from 'node:test';
import assert from 'node:assert/strict';
import {paymentError} from '../../src/js/core/payment-error.js';

test('checkout error shows the explicit JSON reason instead of a generic non-2xx message',async()=>{
  const error=new Error('Edge Function returned a non-2xx status code');
  error.context=new Response(JSON.stringify({error:'Nessun merchant Stripe collegato alla scuola'}),{
    status:409,headers:{'Content-Type':'application/json'}
  });
  const result=await paymentError(error);
  assert.equal(result.message,'Nessun merchant Stripe collegato alla scuola');
});

test('checkout error maps missing JSON to a safe status-specific explanation',async()=>{
  const error=new Error('Edge Function returned a non-2xx status code');
  error.context=new Response('Server error',{status:503});
  const result=await paymentError(error);
  assert.match(result.message,/HTTP 503/);
});

test('checkout error never prints an unexpected JSON payload',async()=>{
  const error=new Error('Edge Function returned a non-2xx status code');
  error.context=new Response(JSON.stringify({apiKey:'do-not-display'}),{status:403});
  const result=await paymentError(error);
  assert.match(result.message,/non autorizzato/);
  assert.doesNotMatch(result.message,/do-not-display/);
});
