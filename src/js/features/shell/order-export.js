// Tenant-scoped CSV export. Uses the current authenticated session and RLS.
const columns=['display_no','created_at','status','payment_status','total_cents'];
export function ordersToCsv(rows){
 const esc=value=>'"'+String(value??'').replaceAll('"','""')+'"';
 return [columns.join(';'),...rows.map(row=>columns.map(k=>esc(row[k])).join(';'))].join('\r\n')+'\r\n';
}
export async function exportSchoolOrdersCsv(client,schoolId,{pageSize=500,maxRows=20000}={}){
 if(!/^[0-9a-f-]{36}$/i.test(String(schoolId)))throw Error('Scuola non valida');
 const rows=[];
 for(let offset=0;offset<maxRows;offset+=pageSize){
  const {data,error}=await client.from('orders')
   .select(columns.join(',')).eq('school_id',schoolId)
   .order('created_at',{ascending:false}).order('id',{ascending:false})
   .range(offset,offset+pageSize-1);
  if(error)throw error;
  rows.push(...(data||[]));
  if((data||[]).length<pageSize)return {csv:ordersToCsv(rows),count:rows.length,truncated:false};
 }
 return {csv:ordersToCsv(rows),count:rows.length,truncated:true};
}
export function downloadCsv(csv,filename){
 const url=URL.createObjectURL(new Blob(['\uFEFF',csv],{type:'text/csv;charset=utf-8'}));
 const anchor=document.createElement('a');
 anchor.href=url;anchor.download=filename;document.body.append(anchor);anchor.click();anchor.remove();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
}
