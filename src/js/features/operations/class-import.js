// Parse the first column of CSV/XLSX without evaluating formulas or macros.
export async function readClassNames(file){
 if(!file||file.size>2*1024*1024)throw new Error('Scegli un file CSV o XLSX di massimo 2 MB.');
 let rows=[];
 if(file.name.toLowerCase().endsWith('.csv'))rows=(await file.text()).replace(/^\uFEFF/,'').split(/\r?\n/).map(line=>line.split(/[;,\t]/)[0].replace(/^"|"$/g,'').trim());
 else if(file.name.toLowerCase().endsWith('.xlsx')){
  const bytes=new Uint8Array(await file.arrayBuffer()),view=new DataView(bytes.buffer);let end=-1;
  for(let i=bytes.length-22;i>=Math.max(0,bytes.length-65557);i--)if(view.getUint32(i,true)===0x06054b50){end=i;break;}
  if(end<0)throw new Error('File Excel non valido.');
  const files=new Map();let pos=view.getUint32(end+16,true);
  for(let n=0;n<view.getUint16(end+10,true);n++){
   if(view.getUint32(pos,true)!==0x02014b50)throw new Error('Archivio Excel non valido.');
   const method=view.getUint16(pos+10,true),size=view.getUint32(pos+20,true),expanded=view.getUint32(pos+24,true),nameLength=view.getUint16(pos+28,true),extra=view.getUint16(pos+30,true),comment=view.getUint16(pos+32,true),offset=view.getUint32(pos+42,true);
   const name=new TextDecoder().decode(bytes.subarray(pos+46,pos+46+nameLength));pos+=46+nameLength+extra+comment;
   if(!/^xl\/(sharedStrings\.xml|worksheets\/sheet1\.xml)$/.test(name))continue;
   if(expanded>4*1024*1024)throw new Error('Foglio Excel troppo grande.');
   const start=offset+30+view.getUint16(offset+26,true)+view.getUint16(offset+28,true),compressed=bytes.slice(start,start+size);
   const data=method===0?compressed:method===8?new Uint8Array(await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer()):null;
   if(!data||data.length>4*1024*1024)throw new Error('Compressione Excel non supportata.');files.set(name,new TextDecoder().decode(data));
  }
  const parse=s=>{const doc=new DOMParser().parseFromString(s||'','application/xml');if(doc.querySelector('parsererror'))throw new Error('Contenuto Excel non valido.');return doc;};
  const strings=files.has('xl/sharedStrings.xml')?[...parse(files.get('xl/sharedStrings.xml')).querySelectorAll('si')].map(si=>si.textContent):[];
  if(!files.has('xl/worksheets/sheet1.xml'))throw new Error('Il primo foglio Excel non è disponibile.');
  rows=[...parse(files.get('xl/worksheets/sheet1.xml')).querySelectorAll('row')].map(r=>{const c=r.querySelector('c');if(!c||!/^A\d+$/.test(c.getAttribute('r')||''))return '';const value=c.querySelector('v')?.textContent||c.querySelector('is')?.textContent||'';return c.getAttribute('t')==='s'?strings[Number(value)]||'':value;});
 }else throw new Error('Formato supportato: CSV o XLSX.');
 const result=[...new Set(rows.map(x=>String(x).trim()).filter(x=>x&&!/^(classe|class|classi|nome classe)$/i.test(x)))];
 if(!result.length||result.length>1000||result.some(x=>x.length>80||/^[=+@]/.test(x)))throw new Error('Controlla nomi e numero delle classi (massimo 1000).');return result;
}
