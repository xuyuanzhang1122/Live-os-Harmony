const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test'),assert=require('node:assert/strict');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root=path.resolve(__dirname,'../../entry/src/main/ets');
const fixtures=path.resolve(__dirname,'../contracts/v2');
const ready=()=>JSON.parse(fs.readFileSync(path.join(fixtures,'v2-session-ready.json'))).value.data;
let clock=0,timers=new Map(),nextTimer=0;
const modules={};
function load(rel){if(modules[rel])return modules[rel];const exports={};modules[rel]=exports;const source=fs.readFileSync(path.join(root,rel+'.ets'),'utf8');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,
 {exports,require:n=>n.startsWith('@')?{}:load(path.posix.normalize(path.posix.join(path.posix.dirname(rel),n))),
 Error,setTimeout:(cb,ms)=>{timers.set(++nextTimer,{cb,ms});return nextTimer;},clearTimeout:id=>timers.delete(id),console,Date});return exports;}
const common=load('model/Common'),v2=load('model/PlaybackV2');
function setup(overrides={}){timers.clear();const calls=[];const session=ready();const client={
 createPlaybackSession:async body=>{calls.push(['create',body]);return {...session};},
 getPlaybackSession:async id=>{calls.push(['get',id]);return {...session,url:session.url+'&fresh=1'};},
 cancelPlaybackSession:async id=>{calls.push(['cancel',id]);},...overrides};
 const {PlayerViewModel}=load('viewmodel/PlayerViewModel'); const model=new PlayerViewModel(client);
 const states=[],errors=[];model.onReady=async s=>states.push(s);model.onError=e=>errors.push(e);
 return {model,client,calls,states,errors,identity:{recording_id:session.recording_id,source_version:session.source_version},caps:{containers:['mp4'],protocols:['file'],video:[],audio:[]}};}
async function tick(){const [id,t]=timers.entries().next().value;timers.delete(id);await t.cb();await new Promise(r=>setImmediate(r));}
test('ready starts refresh before expiry and replaces media authorization',async()=>{const x=setup();await x.model.open(x.identity,x.caps);
 assert.equal(x.states.length,1);assert.equal([...timers.values()][0].ms,240000);await tick();assert.equal(x.states.length,2);assert.ok(x.states[1].url.includes('fresh'));await x.model.close();assert.equal(timers.size,0);});
test('close cancels in-flight create when its response arrives',async()=>{let resolve;const x=setup({createPlaybackSession:()=>new Promise(r=>resolve=r)});
 const task=x.model.open(x.identity,x.caps);await new Promise(r=>setImmediate(r));await x.model.close();resolve(ready());await task;assert.equal(x.states.length,0);assert.equal(x.calls.filter(c=>c[0]==='cancel').length,1);});
test('late old refresh cannot contaminate reopened playback',async()=>{let resolve;const x=setup();await x.model.open(x.identity,x.caps);
 x.client.getPlaybackSession=()=>new Promise(r=>resolve=r);const t=tick();await x.model.close();await x.model.open(x.identity,x.caps);resolve(ready());await t;
 assert.equal(x.states.length,2);await x.model.close();});
test('410 refresh recreates once with the same identity',async()=>{const x=setup({getPlaybackSession:async()=>{throw new v2.V2ApiError(410,{code:'session_expired',message:'expired',retryable:false},'r');}});
 await x.model.open(x.identity,x.caps);await tick();assert.equal(x.calls.filter(c=>c[0]==='create').length,2);await x.model.close();});
test('source_changed is visible and never recreates/falls back',async()=>{const x=setup({getPlaybackSession:async()=>{throw new v2.V2ApiError(409,{code:'source_changed',message:'changed',retryable:false},'r');}});
 await x.model.open(x.identity,x.caps);await tick();assert.equal(x.errors.length,1);assert.equal(x.calls.filter(c=>c[0]==='create').length,1);assert.equal(timers.size,0);await x.model.close();});
test('processing and paused use server interval then ready',async()=>{let i=0;const r=ready();const x=setup({createPlaybackSession:async()=>({...r,status:'paused',url:undefined,retry_after_seconds:2}),getPlaybackSession:async()=>++i===1?{...r,status:'processing',url:undefined,retry_after_seconds:3}:r});
 const task=x.model.open(x.identity,x.caps);await new Promise(r=>setImmediate(r));assert.equal([...timers.values()][0].ms,2000);await tick();assert.equal([...timers.values()][0].ms,3000);await tick();await task;assert.equal(x.states.length,1);await x.model.close();});
test('wrong session identity cannot replace current source',async()=>{const x=setup({getPlaybackSession:async()=>({...ready(),source_version:'changed'})});await x.model.open(x.identity,x.caps);await tick();assert.equal(x.states.length,1);assert.equal(x.errors.length,1);await x.model.close();});
test('transient refresh failure retries without swallowing permanent auth error',async()=>{let n=0;const x=setup({getPlaybackSession:async()=>{if(++n===1)throw common.ApiError.network('offline');throw common.ApiError.unauthorized();}});
 await x.model.open(x.identity,x.caps);await tick();assert.equal(x.errors.length,0);await tick();assert.equal(x.errors.length,1);assert.equal(timers.size,0);await x.model.close();});

test('immediate exit before create continuation never creates or plays',async()=>{const x=setup();const task=x.model.open(x.identity,x.caps);await x.model.close();await task;assert.equal(x.calls.length,0);assert.equal(x.states.length,0);});
test('zero refresh replaces expiring session and cancels old lease',async()=>{let count=0;const r=ready();const x=setup({createPlaybackSession:async()=>({...r,id:++count===1?r.id:'new-session'}),getPlaybackSession:async()=>({...r,refresh_after_seconds:0})});
 await x.model.open(x.identity,x.caps);await tick();assert.equal(count,2);assert.equal(x.states[1].id,'new-session');assert.ok(x.calls.some(c=>c[0]==='cancel'&&c[1]===r.id));await x.model.close();});
test('played asset stays pinned through 410 processing transition',async()=>{
 let creates=0;const r=ready();const x=setup({createPlaybackSession:async()=>++creates===1?r:{...r,id:'new',status:'processing',asset_version:'',url:undefined,retry_after_seconds:2},getPlaybackSession:async(id)=>{if(id===r.id)throw new v2.V2ApiError(410,{code:'session_expired',message:'expired',retryable:false},'r');return {...r,id:'new',asset_version:'changed'};}});
 await x.model.open(x.identity,x.caps);await tick();await tick();assert.equal(x.states.length,1);assert.equal(x.errors.length,1);assert.ok(x.calls.some(c=>c[0]==='cancel'&&c[1]==='new'));await x.model.close();
});
