import test from 'node:test';
import assert from 'node:assert/strict';
import {accuratePosition} from '../../src/js/core/geolocation.js';

function locator(){
  let success,failure;
  const cleared=[];
  return {
    cleared,
    watchPosition(ok,err,options){success=ok;failure=err;this.options=options;return 42;},
    clearWatch(id){cleared.push(id);},
    position(accuracy,overrides={}){success({coords:{latitude:45.5,longitude:9.3,accuracy},timestamp:Date.now(),...overrides});},
    error(code){failure({code});}
  };
}

test('waits for a better location without relaxing the server accuracy limit',async()=>{
  const geo=locator(),progress=[];
  const result=accuratePosition({geolocation:geo,timeoutMs:200,onProgress:x=>progress.push(x)});
  geo.position(320);geo.position(125);geo.position(35);
  assert.equal((await result).coords.accuracy,35);
  assert.deepEqual(progress,[320,125]);
  assert.deepEqual(geo.cleared,[42]);
  assert.deepEqual(geo.options,{enableHighAccuracy:true,maximumAge:0,timeout:200});
});

test('explains the actual accuracy if a usable fix does not arrive',async()=>{
  const geo=locator();
  const result=accuratePosition({geolocation:geo,timeoutMs:10});
  geo.position(245);
  await assert.rejects(result,/±245 m.*entro 100 m/);
  assert.deepEqual(geo.cleared,[42]);
});

test('does not send stale, impossible, or denied location readings',async()=>{
  const denied=locator();
  const failure=accuratePosition({geolocation:denied,timeoutMs:50});
  denied.error(1);
  await assert.rejects(failure,/consenti la posizione/i);
  assert.deepEqual(denied.cleared,[42]);
  const geo=locator();
  const reading=accuratePosition({geolocation:geo,timeoutMs:20});
  geo.position(20,{timestamp:Date.now()-120001});
  geo.position(20,{coords:{latitude:200,longitude:9.3,accuracy:20}});
  await assert.rejects(reading,/non è arrivata in tempo/i);
});

test('closing the checkout cancels the location watch before any order is submitted',async()=>{
  const geo=locator(),controller=new AbortController();
  const pending=accuratePosition({geolocation:geo,timeoutMs:100,signal:controller.signal});
  controller.abort();
  await assert.rejects(pending,{name:'AbortError'});
  assert.deepEqual(geo.cleared,[42]);
});
