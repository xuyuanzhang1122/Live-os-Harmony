const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../../entry/src/main/ets');
let replies = [], calls = [];
const http = {RequestMethod: {GET:'GET',POST:'POST',DELETE:'DELETE'}, HttpDataType:{ARRAY_BUFFER:1},
  createHttp: () => ({request: async (url, options) => {
    calls.push({url,options}); const next = replies.shift();
    if (typeof next === 'function') return next(url, options);
    if (!next) throw Error('unexpected HTTP request');
    return {responseCode:200, ...next, result:typeof next.result === 'object' && !(next.result instanceof ArrayBuffer) ? JSON.stringify(next.result) : next.result};
  },destroy(){}})};
const modules = {};
function load(rel) {
  if (modules[rel]) return modules[rel];
  const exports = {}; modules[rel] = exports;
  const source = fs.readFileSync(path.join(root, rel + '.ets'),'utf8').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,'');
  vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,
    {exports, require: name => name === '@kit.NetworkKit' ? {http} : name.startsWith('@') ? {} :
      load(path.posix.normalize(path.posix.join(path.posix.dirname(rel), name))),
    setTimeout,clearTimeout,ArrayBuffer,console});
  return exports;
}
const {APIClient} = load('net/APIClient');
const {VideoFileInfo} = load('model/VideoLibrary');
const fixturesRoot = path.resolve(__dirname,'../contracts/v2');
const fixture = name => JSON.parse(fs.readFileSync(path.join(fixturesRoot, 'v2-'+name+'.json'))).value;
const enqueue = value => replies.push({result:value});
const client = () => new APIClient('https://server/proxy','secret');
test.beforeEach(() => {replies=[];calls=[];});
test('v2 ready uses play_token without exposing management key', async () => {
  enqueue(fixture('session-ready')); const result = await client().getPlaybackSession('session');
  assert.equal(result.status,'ready'); assert.equal(result.url,'https://server/proxy'+fixture('session-ready').data.url);
  assert.equal(calls[0].options.header.Authorization,'Bearer secret'); assert.ok(!result.url.includes('_key'));
});
for (const status of ['processing','paused','failed','cancelled']) test('shared session '+status, async () => {
  enqueue(fixture('session-'+status)); assert.equal((await client().getPlaybackSession('session')).status,status);
});
test('v2 errors preserve code retryability and request_id', async () => {
  replies.push({responseCode:410,result:fixture('session-expired')});
  await assert.rejects(client().getPlaybackSession('s'),e => e.code==='session_expired' && e.requestId==='example-expired' && e.retryable===false);
});
test('v2 unknown, malformed, signed key and missing token ready fail closed',async () => {
  const base=fixture('session-ready');
  for (const value of [{...base,data:{...base.data,status:'future'}}, {...base,data:{...base.data,url:'/files/a.mp4?_key=secret'}},
    {...base,data:{...base.data,url:undefined}}, {...base,request_id:undefined}, {...base,data:{...base.data,refresh_after_seconds:-1}}]) {
    enqueue(value); await assert.rejects(client().getPlaybackSession('s'));
  }
});
test('v2 create posts shared identity/capability body',async () => {
  enqueue(fixture('session-processing')); const body=fixture('create-session'); await client().createPlaybackSession(body);
  assert.deepEqual(JSON.parse(calls[0].options.extraData),body);
});
test('v2 cancellation consumes cancelled envelope',async () => {
  enqueue(fixture('session-cancelled')); await client().cancelPlaybackSession('s'); assert.equal(calls[0].options.method,'DELETE');
});
test('recordings consumes verified list and server size text',async () => {
  enqueue(fixture('recordings')); const result=await client().getRecordings();
  assert.equal(result.items[0].size_text,'189.0 GB'); assert.equal(result.catalog_status,'verified');
});
test('auto list paginates and preserves v2 identity instead of old URLs',async () => {
  enqueue({...fixture('recordings'),data:{...fixture('recordings').data,next_cursor:'page2'}});
  enqueue({...fixture('recordings'),data:{items:[],next_cursor:'',catalog_status:'verified'}});
  enqueue([{name:'clip.mp4',rel_path:'平台/主播/clip.mp4',mod_time:10,thumbnail_url:'/thumb'}]);
  const files=await client().getVideoFiles('平台/主播');
  assert.equal(files[0].recording_id,fixture('recordings').data.items[0].recording_id);
  assert.equal(files[0].size_text,'189.0 GB'); assert.ok(calls[1].url.includes('after=page2'));
});
test('only proven missing endpoint falls back; unauthorized never falls back', async () => {
  replies.push({responseCode:404,result:'404 page not found'}); enqueue([]);
  await client().getVideoFiles('room'); assert.equal(calls.length,2);
  calls=[];replies.push({responseCode:401,result:fixture('unauthorized')});
  await assert.rejects(client().getVideoFiles('room')); assert.equal(calls.length,1);
});
test('v2 partial delete preserves failure and maps stable ID to path',async () => {
  enqueue(fixture('batch-partial')); const id=fixture('batch-delete').items[0];
  const result=await client().batchDeleteRecordings([new VideoFileInfo({name:'a',rel_path:'a',...id})]);
  assert.equal(result[0].path,'a'); assert.equal(result[0].success,false); assert.equal(result[0].message,'来源版本变化');
  assert.deepEqual(JSON.parse(calls[0].options.extraData),fixture('batch-delete'));
});
test('LAN accepts only actual app info with successful status',async () => {
  for(const reply of [{responseCode:401,result:'unauthorized'},{responseCode:404,result:'oops'}, {result:{app_name:'proxy'}},
    {result:{app_name:'bililive-go',app_version:'2.1.1'}}]) replies.push(reply);
  const c=client(); assert.equal(await c.probeServer(),false);assert.equal(await c.probeServer(),false);
  assert.equal(await c.probeServer(),false);assert.equal(await c.probeServer(),true);
});
test('thumbnail binary request renews expired signature through Bearer API',async()=>{
 replies.push({responseCode:401,result:new ArrayBuffer(0)});
 enqueue({err_no:0,data:{url:'/api/thumbnail/room/clip.mp4?expires=999&sig=fresh'}});
 const expected=new ArrayBuffer(2);replies.push({responseCode:200,result:expected});
 assert.equal(await client().downloadThumbnail('/api/thumbnail/room/clip.mp4?expires=1&sig=old'),expected);
 assert.equal(calls.length,3);assert.equal(calls[1].options.header.Authorization,'Bearer secret');
 assert.ok(calls[1].url.includes('kind=thumbnail'));assert.ok(calls[2].url.includes('sig=fresh'));
});
test('foreign thumbnail never receives management Authorization or key',async()=>{
 replies.push({result:new ArrayBuffer(2)});await client().downloadThumbnail('https://cdn/thumbnail.jpg?expires=999&sig=ok');
 assert.equal(calls[0].options.header.Authorization,undefined);assert.ok(!calls[0].url.includes('secret'));
});
test('shared fixture snapshot and compiled Hypium fixture values remain identical',()=>{
 const fixtures=loadFixtureStrings();for(const [name,value] of Object.entries(fixtures))assert.deepEqual(JSON.parse(value),fixture(name));
 const sibling=path.resolve(__dirname,'../../../bililive-go-UI/docs/contracts/examples');
 if(fs.existsSync(sibling))for(const name of fs.readdirSync(fixturesRoot))assert.equal(fs.readFileSync(path.join(fixturesRoot,name),'utf8'),fs.readFileSync(path.join(sibling,name),'utf8'));
});
function loadFixtureStrings(){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(root,'../../test/V2Fixtures.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports});
 return Object.fromEntries(Object.entries(exports).map(([name,value])=>[name.replace(/^V2/,'').replace(/[A-Z]/g,(m,i)=>i?'-'+m.toLowerCase():m.toLowerCase()),value]));}
test('zero refresh_after_seconds is a legal nearing-expiry server signal',async()=>{
 const f=fixture('session-ready');f.data.refresh_after_seconds=0;enqueue(f);assert.equal((await client().getPlaybackSession('s')).refresh_after_seconds,0);
});

test('Go omitempty near-expiry refresh is normalized only at the session boundary',async()=>{
 const f=fixture('session-ready');delete f.data.refresh_after_seconds;
 f.data.expires_at=Math.floor(Date.now()/1000)+30;f.data.token_expires_at=f.data.expires_at;
 enqueue(f);assert.equal((await client().getPlaybackSession('s')).refresh_after_seconds,0);
 const bad=fixture('session-ready');delete bad.data.refresh_after_seconds;
 bad.data.expires_at=Math.floor(Date.now()/1000)+900;bad.data.token_expires_at=bad.data.expires_at-300;
 enqueue(bad);await assert.rejects(client().getPlaybackSession('s'));
});
