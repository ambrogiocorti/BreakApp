import {readFileSync} from 'node:fs';
const app=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const start=app.indexOf('<section id="groups"');
// Find the matching </section>: the groups page contains nested sections.
let end=start,depth=0;
for(const match of app.slice(start).matchAll(/<section\b|<\/section>/g)){
 depth+=match[0]==='</section>'?-1:1;
 if(depth===0){end=start+match.index+'</section>'.length;break;}
}
const markup=app.slice(start,end);
const script=`
import '/src/css/app.css';
import {initializeGroupDrafts} from '/src/js/features/groups/groups.js';
const school='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',bar='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',group='cccccccc-cccc-4ccc-8ccc-cccccccccccc',user='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const fixture=window.fixture={calls:[],user:{id:user,email:'studente@example.invalid'},callbacks:[],emptyGroups:false,
 detail:{id:group,title:'5A INF',status:'draft',coordinator:true,my_status:'accepted',accepting_members:true,requires_approval:false,max_members:null,school_id:school,bar_id:bar,pickup_window_id:'slot-a',invite_token:'11111111-1111-4111-8111-111111111111',my_ready:false,my_items:[],totals:{count:0,total_cents:0},members:[{member_id:user,status:'accepted',ready:false,line_count:0}]}};
const data={schools:[{id:school,name:'Scuola dimostrativa',is_active:true}],bars:[{id:bar,school_id:school,name:'Bar della scuola',is_active:true}],pickup_windows:[{id:'slot-a',bar_id:bar,service_date:'2026-11-07',starts_at:'10:00:00',ends_at:'10:15:00',is_active:true}],products:[{id:'product-a',school_id:school,bar_id:bar,category_id:'c',name:'Panino',price_cents:250,is_active:true,categories:{is_active:true}},{id:'product-b',school_id:school,bar_id:bar,category_id:'c',name:'Succo',price_cents:150,is_active:true,categories:{is_active:true}}]};
const client={auth:{onAuthStateChange(fn){fixture.callbacks.push(fn);},async getUser(){return{data:{user:fixture.user}}}},
 from(name){let rows=data[name]||[];return{select(){return this;},eq(key,value){if(!key.includes('.'))rows=rows.filter(r=>r[key]===value);return this;},gte(){return this;},order(){return this;},limit(){return this;},then(resolve,reject){return Promise.resolve({data:structuredClone(rows),error:null}).then(resolve,reject);}}},
 async rpc(name,args={}){fixture.calls.push({name,args:structuredClone(args)});
  if(name==='list_my_group_drafts')return{data:fixture.emptyGroups?[]:[{id:group,title:'5A INF',coordinator:true,my_status:'accepted',status:'draft'}]};
  if(name==='group_draft_details')return{data:structuredClone(fixture.detail)};
  if(name==='group_payable_lines')return{data:[]};
  if(name==='replace_group_personal_cart'){fixture.detail.my_items=structuredClone(args.p_items);fixture.detail.totals={count:args.p_items.reduce((n,i)=>n+i.quantity,0),total_cents:args.p_items.reduce((n,i)=>n+i.quantity*(i.product_id==='product-a'?250:150),0)};return{data:null};}
  if(name==='set_group_personal_ready'){fixture.detail.my_ready=args.p_ready;fixture.detail.members[0].ready=args.p_ready;return{data:null};}
  if(name==='join_group_draft'||name==='create_group_draft')return{data:group};
  return{data:null};},functions:{async invoke(){return{data:{error:'Pagamento non disponibile nel test'}};}}};
document.body.dataset.authenticated='true';initializeGroupDrafts(client);
fixture.setGuest=()=>{fixture.user={id:user,app_metadata:{guest:true}};fixture.callbacks.forEach(fn=>fn('SIGNED_IN',{user:fixture.user}));};
`;
export const groupFixture='<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Gruppi · BreakApp</title></head><body><main>'+markup+'</main><script type="module">'+script+'</script></body></html>';
