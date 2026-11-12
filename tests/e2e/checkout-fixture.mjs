import {readFileSync} from 'node:fs';
const app=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const script=`
import '/src/css/app.css';
import {initializeOrders} from '/src/js/features/orders/orders.js';
const user={id:'fixture-user',email:'studente@example.invalid'},school='school-a',bar='bar-a';
const fixture=window.fixture={calls:[],callbacks:[],cleared:[],user,watch:null};
Object.defineProperty(navigator,'geolocation',{configurable:true,value:{watchPosition(ok,err,options){fixture.watch={ok,err,options};return 17;},clearWatch(id){fixture.cleared.push(id);fixture.watch=null;}}});
fixture.position=accuracy=>fixture.watch?.ok({coords:{latitude:45.5,longitude:9.3,accuracy},timestamp:Date.now()});
fixture.logout=()=>{fixture.user=null;fixture.callbacks.forEach(fn=>fn('SIGNED_OUT',null));};
const products=[{id:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',school_id:school,bar_id:bar,name:'Panino',price_cents:250,is_active:true}];
const data={orders:[],school_memberships:[],customer_favorites:[],pickup_windows:[{id:'slot-a',bar_id:bar,service_date:'2030-11-05',starts_at:'10:00:00',ends_at:'10:15:00',is_active:true}],bar_closures:[],bar_opening_hours:Array.from({length:7},(_,weekday)=>({bar_id:bar,weekday,starts_at:'08:00:00',ends_at:'13:00:00'})),bar_service_state:[{bar_id:bar,accepting_orders:true,reason:null}]};
const client={auth:{onAuthStateChange(fn){fixture.callbacks.push(fn);},async getUser(){return{data:{user:fixture.user}}},mfa:{async getAuthenticatorAssuranceLevel(){return{data:{currentLevel:'aal1'}}}}},
 from(name){let rows=data[name]||[];return{select(){return this;},eq(key,value){rows=rows.filter(x=>x[key]===value);return this;},in(){return this;},gte(key,value){rows=rows.filter(x=>x[key]>=value);return this;},is(){return this;},order(){return this;},limit(){return this;},range(){return this;},maybeSingle(){return Promise.resolve({data:rows[0]||null,error:null});},then(ok,err){return Promise.resolve({data:structuredClone(rows),error:null}).then(ok,err);}}},
 async rpc(name,args){fixture.calls.push({name,args:structuredClone(args)});if(name==='submit_promoted_order')return{data:'order-fixture',error:null};return{data:[],error:null};},functions:{async invoke(){return{data:{},error:null}}}};
document.body.dataset.authenticated='true';document.getElementById('signed-out-view').hidden=true;document.getElementById('signed-in-view').hidden=false;
initializeOrders(client);
const demoAdd=document.createElement('button');demoAdd.textContent='Aggiungi panino di prova';demoAdd.type='button';demoAdd.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:quick-add',{detail:{id:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',barId:bar}})));document.body.insertBefore(demoAdd,document.body.firstChild);
setTimeout(()=>{window.dispatchEvent(new CustomEvent('breakapp:catalog-ready',{detail:{schoolId:school,barId:bar,products}}));fixture.ready=true;},0);
`;
export const checkoutFixture=app.replaceAll('%BASE_URL%','/').replace('<script type="module" src="/src/js/main.js"></script>','<script type="module">'+script+'</script>');
