import {readFileSync} from 'node:fs';
// Real application markup and controllers, backed only by an isolated API fixture.
// This module is used by tests; it is never imported by the application build.
const app=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const script=`
import '/src/css/base.css';import '/src/css/workspace.css';
import {initializeTheme} from '/src/js/core/theme.js';
import {initializeWorkspace} from '/src/js/features/shell/workspace.js';
import {initializeWorkspaceDashboards} from '/src/js/features/shell/dashboards.js';
import {initializePlatformPilot} from '/src/js/features/shell/platform-pilot.js';
import {initializeCompletionUI} from '/src/js/features/operations/completion-ui.js';
import {initializeOrderWorkflows} from '/src/js/features/operations/workflows.js';
const schools=[{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',name:'ITSOS Marie Curie',is_active:true,latitude:45.52,longitude:9.33},{id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',name:'Liceo Leonardo',is_active:true,latitude:45.5,longitude:9.3},{id:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',name:'Istituto Ada Lovelace',is_active:false,latitude:45.5,longitude:9.3}];
const bars=[{id:'bar-a',school_id:schools[0].id,name:'Bar centrale',is_active:true},{id:'bar-b',school_id:schools[0].id,name:'Caffè del cortile',is_active:true},{id:'bar-c',school_id:schools[1].id,name:'Bar Leonardo',is_active:true},{id:'bar-d',school_id:schools[2].id,name:'Bar Ada',is_active:true}];
const user={id:'fixture-user',email:'ambrogio@example.invalid'},callbacks=[];
window.fixture={calls:[],platform:true,user,fail:false,delay:0};
const data={schools,bars,school_memberships:[],categories:[{id:'cat-a',school_id:schools[0].id,bar_id:'bar-a',name:'Panini',is_active:true}],products:[{id:'product-a',school_id:schools[0].id,bar_id:'bar-a',category_id:'cat-a',name:'Panino mozzarella',price_cents:300,ingredients:'Pane, mozzarella, pomodoro',allergens:['gluten','milk'],is_active:true}],bar_opening_hours:[{school_id:schools[0].id,bar_id:'bar-a',weekday:1,starts_at:'08:00:00',ends_at:'14:00:00'}],pickup_windows:[],daily_stock:[],orders:[],bar_service_state:[]};
const client={auth:{onAuthStateChange(fn){callbacks.push(fn);return {data:{subscription:{unsubscribe(){}}}}},async getUser(){return {data:{user:window.fixture.user}}},mfa:{async getAuthenticatorAssuranceLevel(){return {data:{currentLevel:'aal2'}}}}},
 async rpc(name,args){window.fixture.calls.push({name,args});if(name==='has_current_platform_admin_role'||name==='is_current_platform_admin')return{data:window.fixture.platform};if(name==='platform_set_school_active'){schools.find(s=>s.id===args.p_school).is_active=args.p_active;return{data:null}}if(name==='platform_onboard_school')return{data:{school_id:schools[0].id,bar_id:'bar-a'}};return{data:[]}},
 from(name){let rows=data[name]||[];return{select(){return this},eq(key,value){rows=rows.filter(r=>r[key]===value);return this},in(){return this},gte(){return this},order(){return this},limit(n){rows=rows.slice(0,n);return this},range(start,end){rows=rows.slice(start,end+1);return this},async then(resolve,reject){const wait=window.fixture.delay;if(wait)await new Promise(done=>setTimeout(done,wait));return Promise.resolve(window.fixture.fail?{error:{message:'Fixture offline'}}:{data:structuredClone(rows)}).then(resolve,reject)}}}
};
document.body.dataset.authenticated='true';document.getElementById('signed-out-view').hidden=true;document.getElementById('signed-in-view').hidden=false;
initializeTheme();initializeWorkspaceDashboards(client);initializePlatformPilot(client);initializeCompletionUI(client);initializeOrderWorkflows(client);initializeWorkspace(client);
window.fixture.logout=()=>{window.fixture.user=null;for(const fn of callbacks)fn('SIGNED_OUT',null)};
window.fixture.customer=()=>{window.fixture.platform=false;window.dispatchEvent(new CustomEvent('breakapp:access-updated'))};
window.fixture.ready=true;
`;
export const workspaceFixture=app.replaceAll('%BASE_URL%','/').replace('<script type="module" src="/src/js/main.js"></script>','<script type="module">'+script+'</script>');
