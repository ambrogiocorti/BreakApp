import test from 'node:test';
import assert from 'node:assert/strict';
import {firstCSVColumn,readClassNames} from '../../src/js/features/operations/class-import.js';
test('CSV first column handles quoted separators, escaped quotes and CRLF',()=>{
 assert.deepEqual(firstCSVColumn('\uFEFFClasse;Nome\r\n"5,A";One\r\n"5""B";Two\r\n'),['Classe','5,A','5"B']);
 assert.deepEqual(firstCSVColumn('Classe\tOther\n5A\tX'),['Classe','5A']);
 assert.throws(()=>firstCSVColumn('"bad'),/Virgolette/);
});
test('class import deduplicates names and refuses formulas and oversized files',async()=>{
 assert.deepEqual(await readClassNames(new File(['Classe\n5A\n5A\n5B'],'classi.csv')),['5A','5B']);
 await assert.rejects(readClassNames(new File(['Classe\n=1+1'],'classi.csv')),/Controlla/);
 await assert.rejects(readClassNames(new File([new Uint8Array(2097153)],'classi.csv')),/2 MB/);
});
