// Small standards-based exports. XLSX uses inline strings (never formulas).
// ZIP entries are stored, keeping the frontend free of spreadsheet dependencies.
const utf8=new TextEncoder();
const xml=value=>String(value??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'')
 .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const column=n=>{let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;};
function crc32(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let n=0;n<8;n++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function zip(files){
 const chunks=[],directory=[];let offset=0;
 const header=(size)=>{const bytes=new Uint8Array(size);return [bytes,new DataView(bytes.buffer)];};
 for(const [name,text] of files){
  const path=utf8.encode(name),data=utf8.encode(text),crc=crc32(data),[local,v]=header(30+path.length);
  v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x800,true);
  v.setUint32(14,crc,true);v.setUint32(18,data.length,true);v.setUint32(22,data.length,true);
  v.setUint16(26,path.length,true);local.set(path,30);
  const [central,c]=header(46+path.length);
  c.setUint32(0,0x02014b50,true);c.setUint16(4,20,true);c.setUint16(6,20,true);c.setUint16(8,0x800,true);
  c.setUint32(16,crc,true);c.setUint32(20,data.length,true);c.setUint32(24,data.length,true);
  c.setUint16(28,path.length,true);c.setUint32(42,offset,true);central.set(path,46);
  chunks.push(local,data);directory.push(central);offset+=local.length+data.length;
 }
 const length=directory.reduce((sum,x)=>sum+x.length,0),[end,e]=header(22);
 e.setUint32(0,0x06054b50,true);e.setUint16(8,files.length,true);e.setUint16(10,files.length,true);
 e.setUint32(12,length,true);e.setUint32(16,offset,true);
 const all=[...chunks,...directory,end],out=new Uint8Array(offset+length+end.length);let i=0;
 for(const chunk of all){out.set(chunk,i);i+=chunk.length;}return out;
}
export function workbookBytes(sheets){
 if(!Array.isArray(sheets)||!sheets.length||sheets.length>10)throw Error('Fogli non validi');
 const ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
 const rel='http://schemas.openxmlformats.org/package/2006/relationships';
 const sheetType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';
 const files=[['[Content_Types].xml',`<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${sheets.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="${sheetType}"/>`).join('')}</Types>`],
 ['_rels/.rels',`<?xml version="1.0"?><Relationships xmlns="${rel}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
 ['xl/workbook.xml',`<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="${ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map((s,i)=>`<sheet name="${xml(s.name.slice(0,31))}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')}</sheets></workbook>`],
 ['xl/_rels/workbook.xml.rels',`<?xml version="1.0"?><Relationships xmlns="${rel}">${sheets.map((_,i)=>`<Relationship Id="rId${i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join('')}</Relationships>`]];
 for(const [i,sheet] of sheets.entries()){
  if(sheet.rows.length>20001)throw Error('Troppe righe da esportare');
  const rows=sheet.rows.map((row,r)=>`<row r="${r+1}">${row.map((value,c)=>{
   const ref=column(c)+(r+1);
   return typeof value==='number'&&Number.isFinite(value)?`<c r="${ref}"><v>${value}</v></c>`:
    `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;
  }).join('')}</row>`).join('');
  files.push([`xl/worksheets/sheet${i+1}.xml`,`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="${ns}"><sheetData>${rows}</sheetData></worksheet>`]);
 }
 return zip(files);
}
export function csvTable(rows){
 return '\uFEFF'+rows.map(row=>row.map(value=>{
  let text=String(value??'');if(typeof value!=='number'&&/^\s*[=+@-]/.test(text))text="'"+text;
  return '"'+text.replaceAll('"','""')+'"';
 }).join(';')).join('\r\n')+'\r\n';
}
export function pdfBytes(lines){
 const safe=text=>String(text).replaceAll('€','EUR').normalize('NFKC').replace(/[^\x20-\xff]/g,'?')
  .replaceAll('\\','\\\\').replaceAll('(','\\(').replaceAll(')','\\)');
 const wrapped=lines.flatMap(line=>String(line).match(/.{1,100}/g)||['']);
 const pages=[];for(let n=0;n<wrapped.length;n+=48)pages.push(wrapped.slice(n,n+48));
 if(!pages.length)pages.push(['']);
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'];
 const kids=[];
 for(const [i,page] of pages.entries()){
  const pageId=objects.length+1,streamId=pageId+1;kids.push(pageId+' 0 R');
  const stream='BT /F1 10 Tf 40 800 Td 15 TL\n'+page.map(line=>'('+safe(line)+') Tj T*').join('\n')+
   '\n(Pagina '+(i+1)+' / '+pages.length+') Tj\nET';
  objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${streamId} 0 R >>`,
   `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
 }
 objects[1]='<< /Type /Pages /Count '+pages.length+' /Kids ['+kids.join(' ')+'] >>';
 let content='%PDF-1.4\n';const positions=[0];
 for(const [i,obj] of objects.entries()){positions.push(content.length);content+=(i+1)+' 0 obj\n'+obj+'\nendobj\n';}
 const start=content.length;content+='xref\n0 '+(objects.length+1)+'\n0000000000 65535 f \n';
 for(const pos of positions.slice(1))content+=String(pos).padStart(10,'0')+' 00000 n \n';
 content+='trailer << /Size '+(objects.length+1)+' /Root 1 0 R >>\nstartxref\n'+start+'\n%%EOF\n';
 return Uint8Array.from(content,c=>c.charCodeAt(0));
}
export function downloadReport(data,type,filename){
 const url=URL.createObjectURL(new Blob([data],{type})),a=document.createElement('a');
 a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
}
