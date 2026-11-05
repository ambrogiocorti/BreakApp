import {readFileSync} from 'node:fs';
import {createServer} from 'vite';
// Serves the real index.html with the demo bootstrap instead of src/js/main.js.
export async function startDemoServer(port=5190){
 const app=readFileSync(new URL('../../../index.html',import.meta.url),'utf8');
 const html=app.replaceAll('%BASE_URL%','/').replace('<script type="module" src="/src/js/main.js"></script>','<script type="module" src="/tests/e2e/support/demo-main.js"></script>');
 if(html===app)throw new Error('Demo bootstrap not injected: main script tag changed');
 const server=await createServer({base:'/',logLevel:'error',server:{host:'127.0.0.1',port,strictPort:true},plugins:[{name:'demo',configureServer(vite){vite.middlewares.use('/__demo',async(req,res)=>{res.setHeader('Content-Type','text/html');res.end(await vite.transformIndexHtml(req.originalUrl,html));});}}]});
 await server.listen();
 return {server,origin:'http://127.0.0.1:'+port};
}
