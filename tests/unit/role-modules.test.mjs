import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRoleModuleLoader,STAFF_ROLES,STAFF_DEVICE_KEY} from '../../src/js/role-modules.js';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
function memoryStorage(){const m=new Map();return{getItem:k=>m.has(k)?m.get(k):null,setItem:(k,v)=>m.set(k,String(v)),map:m};}
function fakeImport(){
  const calls={imports:0,inits:[]};
  return {calls,importStaff:async()=>{calls.imports++;return {initializeStaffModules:c=>calls.inits.push(c)};}};
}

test('customers never load the staff chunk',()=>{
  const {calls,importStaff}=fakeImport(),storage=memoryStorage();
  const loader=createRoleModuleLoader('client',{importStaff,storage});
  assert.equal(loader.prepare('customer'),null);
  assert.equal(loader.prepare(undefined),null);
  assert.equal(calls.imports,0);
  assert.equal(storage.map.size,0);
  assert.equal(loader.warm(),false);
  assert.equal(calls.imports,0);
});

test('every staff role waits for the controllers, initialized exactly once',async()=>{
  for(const role of STAFF_ROLES){
    const {calls,importStaff}=fakeImport(),storage=memoryStorage();
    const loader=createRoleModuleLoader('client',{importStaff,storage});
    const first=loader.prepare(role),second=loader.prepare(role);
    assert.ok(first instanceof Promise);
    await Promise.all([first,second]);
    assert.equal(calls.imports,1);
    assert.deepEqual(calls.inits,['client']);
    assert.equal(loader.loaded,true);
    assert.equal(loader.prepare(role),null,'already loaded: apply synchronously');
    assert.equal(storage.getItem(STAFF_DEVICE_KEY),'1');
  }
});

test('a failed download is retried and never initializes twice',async()=>{
  let fail=true,inits=0;
  const loader=createRoleModuleLoader('client',{storage:memoryStorage(),importStaff:async()=>{
    if(fail)throw new Error('offline');return {initializeStaffModules:()=>inits++};
  }});
  await assert.rejects(loader.prepare('bartender'));
  assert.equal(loader.loaded,false);
  fail=false;
  await loader.prepare('bartender');
  await loader.prepare('school_admin');
  assert.equal(inits,1);
});

test('a device that opened a staff context prefetches the chunk at startup',async()=>{
  const {calls,importStaff}=fakeImport(),storage=memoryStorage();
  storage.setItem(STAFF_DEVICE_KEY,'1');
  const loader=createRoleModuleLoader('client',{importStaff,storage});
  assert.equal(loader.warm(),true);
  await loader.prepare('bartender')??Promise.resolve();
  assert.equal(calls.imports,1);
  assert.equal(calls.inits.length,1);
});

test('storage errors do not block loading',async()=>{
  const {calls,importStaff}=fakeImport();
  const storage={getItem(){throw new Error('denied');},setItem(){throw new Error('denied');}};
  const loader=createRoleModuleLoader('client',{importStaff,storage});
  assert.equal(loader.warm(),false);
  await loader.prepare('warehouse_manager');
  assert.equal(calls.inits.length,1);
});

test('staff controllers are split from the customer entry point',()=>{
  const main=read('src/js/main.js'),staff=read('src/js/staff-modules.js');
  for(const name of ['initializeBarService','initializeWarehouseInventory','initializeWorkspaceDashboards',
    'initializePlatformPilot','initializeGroupService','initializeOfflineTerminal','initializeOfflineReview',
    'initializeCashWorkspace','initializeReports']){
    assert.doesNotMatch(main,new RegExp(name),name+' must not be in the customer entry');
    assert.match(staff,new RegExp(name+'\\('),name+' must be initialized by the staff chunk');
  }
  // Shared screens stay in the entry point: customers use them too.
  for(const name of ['initializeOrders','initializePickupQr','initializeOrderWorkflows','initializeCompletionUI',
    'initializeSupportCenter','initializeGroupDrafts'])
    assert.match(main,new RegExp(name+'\\(client\\)'));
  assert.match(read('src/js/role-modules.js'),/import\('\.\/staff-modules\.js'\)/);
  // The offline cash link is preserved inside the chunk.
  assert.match(staff,/initializeCashWorkspace\(client,offlineTerminal\)/);
});

test('workspace applies a staff context only after its controllers load, and fails closed',()=>{
  const shell=read('src/js/features/shell/workspace.js');
  assert.match(shell,/export function initializeWorkspace\(client,\{prepareRole=null\}=\{\}\)/);
  const gate=shell.slice(shell.indexOf('function setContext('),shell.indexOf('function applyContext('));
  assert.match(gate,/request===contextRequest&&token===epoch\)applyContext/);
  assert.match(gate,/Fail closed/);
  assert.doesNotMatch(gate.split('},()=>{')[1]||'',/applyContext/,'a failed load must not open staff sections');
});
