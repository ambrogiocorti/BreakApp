// Rewrites only generated public PWA files for a project-site subdirectory.
// GitHub Pages project URLs generally use /<repository>/; custom domains use /.
import { readFile,writeFile,copyFile,access } from 'node:fs/promises';
import { join } from 'node:path';

const raw=process.env.GITHUB_PAGES_BASE || '/BreakApp/';
if(!/^\/(?:[a-zA-Z0-9._~-]+\/)*$/.test(raw))throw Error('Invalid GitHub Pages base path');
const base=raw.endsWith('/')?raw:raw+'/';
const dir='dist';
const manifestPath=join(dir,'manifest.webmanifest');
const manifest=JSON.parse(await readFile(manifestPath,'utf8'));
manifest.start_url=base;
manifest.scope=base;
for(const icon of manifest.icons??[]){
  icon.src=base+String(icon.src||'').replace(/^\//,'');
}
await writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');
await writeFile(join(dir,'.nojekyll'),'');
await copyFile(join(dir,'index.html'),join(dir,'404.html'));

const html=await readFile(join(dir,'index.html'),'utf8');
if(!html.includes(base+'manifest.webmanifest') || !html.includes(base+'icon-placeholder.svg')) {
 throw Error('Asset prefixes do not match configured Pages base');
}
const sw=await readFile(join(dir,'sw.js'),'utf8');
if(!sw.includes("new URL('./', self.location.href).pathname"))throw Error('Service worker is not scoped to its directory');
console.log('GitHub Pages prepared for',base);
