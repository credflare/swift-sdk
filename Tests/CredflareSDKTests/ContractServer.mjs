import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
const fixtures = process.argv[2];
let redirectHits = 0, uploadSource = '', requestKey = '', droppedSubmit = false;
const requests = [];
const progress = {};
const trap = createServer((req,res) => { redirectHits++; res.end('{}'); }).listen(0,'127.0.0.1');
const sessions = {'Bearer selfie':'facial-session','Bearer capture':'capture-session','Bearer combined':'combined-session'};
function caseSession(token) {
 const step = progress[token] ?? 0;
 if (step === 0) return ['questionnaire-session',200];
 if (token === 'Bearer refresh-fail') return ['unauthorized',401];
 if (token === 'Bearer closes') return ['session-closed',409];
 if (step === 1) return ['requirement-added-session',200];
 return ['requirement-added-session',200,(json) => { json.data.profile.verification_requirements = []; return json; }];
}
function route(req, token, body) {
 if (token === 'Bearer unauthorized') return ['unauthorized',401];
 if (req.url.endsWith('-codes')) return [req.url.endsWith('/phone-codes') ? 'phone-code-request' : 'email-code-request',202];
 if (req.url.endsWith('-codes/confirm')) { if (progress[token]) progress[token] = 2; return ['email-code-confirm',201]; }
 if (['Bearer questionnaire','Bearer refresh-fail','Bearer closes'].includes(token)) {
  if (req.method === 'GET') return caseSession(token);
  if (req.url.endsWith('/submit')) { progress[token] = 1; return ['questionnaire-submission',201]; }
 }
 if (token === 'Bearer hidden-answer' && req.url.endsWith('/submit')) return ['questionnaire-hidden-answer',422];
 if (req.method === 'DELETE') return ['cancelled',200];
 if (req.url.endsWith('/liveness-challenges')) return ['liveness-challenge',201];
 if (req.url.endsWith('/uploads/documents')) return ['upload',201];
 if (req.url.endsWith('/uploads/biometrics')) {
  if (body.includes('name="type"\r\n\r\ngesture')) return ['gesture-upload',201];
  if (body.includes('name="type"\r\n\r\nliveness_video')) return ['video-upload',201];
  return ['selfie-upload',201];
 }
 if (req.url.endsWith('/submit')) {
  if (body.includes('"location_verification"')) {
   if (token === 'Bearer location-reject') return ['location-rejection',422];
   if (token === 'Bearer reference-reject') return ['reference-rejection',422];
   return ['location-submission',201];
  }
  return [body.includes('"facial_verification"') ? 'facial-submission' : 'submission',201];
 }
 return [sessions[token] ?? 'capture-snapshot-or-upload',200];
}
const server = createServer(async (req,res) => {
 const token = req.headers.authorization;
 if (req.url === '/stats') {res.setHeader('Content-Type','application/json');return res.end(JSON.stringify({redirectHits,uploadSource,requestKey,requests}));}
 if (token === 'Bearer redirect') {res.writeHead(302,{Location:`http://127.0.0.1:${trap.address().port}/`});return res.end();}
 if (token === 'Bearer slow') {return setTimeout(() => {res.writeHead(200);res.end('{}');},2000);}
 if (token === 'Bearer broken-body') {res.writeHead(200,{'Content-Type':'application/json','Content-Length':'100000'});res.flushHeaders();res.write('{"success":');return setTimeout(()=>res.destroy(),40);}
 if (token === 'Bearer bad-json') {res.writeHead(200);return res.end('not-json');}
 const chunks=[];for await(const chunk of req)chunks.push(chunk);
 const body=Buffer.concat(chunks).toString('latin1');
 if(req.url.endsWith('/uploads/documents')){uploadSource=body.includes('name="capture_source"\r\n\r\nupload')?'upload':'unknown';requestKey=req.headers['x-idempotency-key'];}
 const write = req.method === 'POST' && (req.url.includes('/uploads/') || req.url.endsWith('/submit'));
 if (write && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(req.headers['x-idempotency-key'] ?? '')) {
  res.writeHead(422,{'Content-Type':'application/json'});
  return res.end(JSON.stringify({success:false,message:'Send an X-Idempotency-Key header with a new UUID for each request, and reuse it only to retry that request.'}));
 }
 requests.push({method:req.method,path:req.url,key:req.headers['x-idempotency-key'] ?? null,contentType:req.headers['content-type'] ?? null,body:body.length > 4096 ? body.slice(0,4096) : body});
 if (token === 'Bearer drop-submit' && req.url.endsWith('/submit') && !droppedSubmit) {droppedSubmit = true;return req.socket.destroy();}
 const rejection = /^Bearer reject:([a-z_.]+)$/.exec(token ?? '');
 if (rejection && req.method === 'POST') {res.writeHead(422,{'Content-Type':'application/json'});return res.end(await readFile(join(fixtures,'rejections',rejection[1]+'.json')));}
 const [fixture,status,change] = route(req, token, body);
 res.writeHead(status,{'Content-Type':'application/json'});
 const raw = await readFile(join(fixtures,fixture+'.json'));
 res.end(change ? JSON.stringify(change(JSON.parse(raw))) : raw);
});
server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
