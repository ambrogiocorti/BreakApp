import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {ALLOWED_PAYMENT_METHODS,activeConfiguration,pickPaymentMethodTypes,appendPaymentMethodTypes}
 from '../../supabase/functions/_shared/payment-methods.mjs';

const on={available:true},off={available:false};

test('only card and the chosen wallets are ever allowed',()=>{
 assert.deepEqual([...ALLOWED_PAYMENT_METHODS],['card','paypal','satispay','revolut_pay']);
 for(const banned of ['link','klarna','amazon_pay','ideal','multibanco','eps','bancontact','sepa_debit'])
  assert.ok(!ALLOWED_PAYMENT_METHODS.includes(banned),banned+' must not be offered');
});

test('methods active on the bar account but not chosen are dropped',()=>{
 const config={card:on,link:on,klarna:on,amazon_pay:on,ideal:on,multibanco:on,eps:on,revolut_pay:on,paypal:off};
 assert.deepEqual(pickPaymentMethodTypes(config),['card','revolut_pay']);
});

test('chosen wallets appear only when the bar has them active',()=>{
 assert.deepEqual(pickPaymentMethodTypes({card:on,paypal:on,satispay:on,revolut_pay:on}),
  ['card','paypal','satispay','revolut_pay']);
 assert.deepEqual(pickPaymentMethodTypes(null),['card']);
 assert.deepEqual(pickPaymentMethodTypes({}),['card']);
});

test('the default active configuration of the bar account is used',()=>{
 const a={id:'pmc_a',active:true,is_default:false},b={id:'pmc_b',active:true,is_default:true};
 assert.equal(activeConfiguration({data:[a,b]}).id,'pmc_b');
 assert.equal(activeConfiguration({data:[{id:'x',active:false,is_default:true},a]}).id,'pmc_a');
 assert.equal(activeConfiguration({data:[]}),null);
 assert.equal(activeConfiguration(undefined),null);
});

test('payment_method_types are sent as an explicit form list',()=>{
 const form=appendPaymentMethodTypes(new URLSearchParams({mode:'payment'}),['card','revolut_pay']);
 assert.equal(form.get('payment_method_types[0]'),'card');
 assert.equal(form.get('payment_method_types[1]'),'revolut_pay');
 assert.equal(form.get('payment_method_types[2]'),null);
});

for(const name of ['stripe-checkout-individual','stripe-checkout-group']){
 test(name+' restricts payment methods before creating the session',async()=>{
  const source=await readFile('supabase/functions/'+name+'/index.ts','utf8');
  const restrict=source.indexOf('appendPaymentMethodTypes(');
  const create=source.indexOf("stripe('checkout/sessions',");
  assert.ok(restrict>0&&create>restrict,'payment methods must be set before the session is created');
  assert.match(source,/payment_method_configurations/);
  assert.match(source,/catch\{\s*return \['card'\];/);
 });
}
