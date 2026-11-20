import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
const fixtures = process.argv[2];
let redirectHits = 0, uploadSource = '', requestKey = '', selfieBody = '', selfieUpload = '', selfieKey = '';
const trap = createServer((req,res) => { redirectHits++; res.end('{}'); }).listen(0,'127.0.0.1');
const server = createServer(async (req,res) => {
 const token = req.headers.authorization;
 if (req.url === '/stats') {res.setHeader('Content-Type','application/json');return res.end(JSON.stringify({redirectHits,uploadSource,requestKey,selfieBody,selfieUpload,selfieKey}));}
 if (token === 'Bearer redirect') {res.writeHead(302,{Location:`http://127.0.0.1:${trap.address().port}/`});return res.end();}
 if (token === 'Bearer slow') {return setTimeout(() => {res.writeHead(200);res.end('{}');},2000);}
 if (token === 'Bearer broken-body') {res.writeHead(200,{'Content-Type':'application/json','Content-Length':'100000'});res.flushHeaders();res.write('{"success":');return setTimeout(()=>res.destroy(),40);}
 if (token === 'Bearer bad-json') {res.writeHead(200);return res.end('not-json');}
 const chunks=[];for await(const chunk of req)chunks.push(chunk);
 const body=Buffer.concat(chunks).toString();
 if(req.url.endsWith('/uploads/documents')){uploadSource=body.includes('name="capture_source"\r\n\r\nupload')?'upload':'unknown';requestKey=req.headers['x-idempotency-key'];}
 if(req.url.endsWith('/uploads/biometrics')) {selfieUpload=body;selfieKey=req.headers['x-idempotency-key'];}
 if(req.url.endsWith('/submit') && body.includes('facial_verification')) selfieBody=body;
 const fixture = token === 'Bearer unauthorized' ? 'unauthorized' : req.url.endsWith('/submit') ? (body.includes('facial_verification')?'facial-submission':'submission') : req.url.endsWith('/uploads/biometrics')?'facial-upload' : req.url.endsWith('/uploads/documents') ? 'upload' : token === 'Bearer selfie' ? 'facial-session' : 'capture-snapshot-or-upload';
 res.writeHead(fixture==='unauthorized'?401:['capture-snapshot-or-upload','facial-session'].includes(fixture)?200:201,{'Content-Type':'application/json'});
 if(req.method==='DELETE')return res.end(await readFile(join(fixtures,'cancelled.json')));
 res.end(await readFile(join(fixtures,fixture+'.json')));
});
server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
