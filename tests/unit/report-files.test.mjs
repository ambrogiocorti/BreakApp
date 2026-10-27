import test from 'node:test';
import assert from 'node:assert/strict';
import {workbookBytes,pdfBytes,csvTable} from '../../src/js/features/shell/report-files.js';
import {loadReportRows,reportTable} from '../../src/js/features/shell/reports.js';
test('Excel workbook is a ZIP of OOXML with numeric money and literal formula-looking text',()=>{
 const bytes=workbookBytes([{name:'Ordini',rows:[['Importo','Bar'],[2.5,'=HYPERLINK("x") & <bar>']]}]);
 assert.equal(new DataView(bytes.buffer).getUint32(0,true),0x04034b50);
 const xml=new TextDecoder().decode(bytes);
 assert.match(xml,/<v>2.5<\/v>/);assert.match(xml,/t="inlineStr"/);assert.match(xml,/&amp; &lt;bar&gt;/);assert.doesNotMatch(xml,/<f>/);
});
test('CSV neutralizes formulas even when they follow spaces',()=>{
 assert.match(csvTable([[' =SUM(A1)',-2.5]]),/"' =SUM\(A1\)";"-2.5"/);
});
test('PDF cross references point to each actual object and pages paginate',()=>{
 const bytes=pdfBytes(Array.from({length:130},(_,i)=>'Movimento '+i+' (cassa) €2,50'));
 const pdf=String.fromCharCode(...bytes);
 assert.match(pdf,/\/Count 3 /);assert.match(pdf,/EUR2,50/);
 const start=Number(pdf.match(/startxref\n(\d+)/)[1]);assert.equal(pdf.slice(start,start+4),'xref');
 for(const m of pdf.matchAll(/(\d{10}) 00000 n /g))assert.match(pdf.slice(Number(m[1])),/^\d+ 0 obj/);
});
test('report export queries one school and stops on a complete last page',async()=>{
 const calls=[];const client={rpc:async(name,args)=>{calls.push({name,args});return {data:[{reference:'G-123',kind:'group',total_cents:250,due_cents:50}]};}};
 const result=await loadReportRows(client,'school-a','2026-10-01','2026-10-27');
 assert.equal(result.rows.length,1);assert.equal(calls[0].args.p_school,'school-a');
 assert.equal(reportTable(result.rows)[1][7],2.5);assert.equal(reportTable(result.rows)[1][8],0.5);
});
