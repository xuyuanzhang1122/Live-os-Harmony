const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict'),test=require('node:test');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root=path.resolve(__dirname,'../../entry/src/main/ets');
function probe(raw){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'player/PlayerCapabilities.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports,Error,require:name=>name==='@kit.PerformanceAnalysisKit'?{hilog:{info(){}}}:{default:{query:()=>raw}}});return exports.PlayerCapabilities.detect();}
test('missing codec capability fails closed without claiming HEVC/HDR',()=>{const c=probe('{}');assert.equal(c.video.length,0);assert.equal(c.audio.length,0);});
test('runtime query reports only conservative confirmed baseline',()=>{const c=probe(JSON.stringify({profiles:['baseline','high'],fps:60,level:42,aac:true}));
 assert.equal(c.video[0].codec,'h264');assert.equal(c.video[0].max_bit_depth,8);assert.equal(c.video[0].hdr,false);assert.equal(c.video[0].max_level,42);assert.deepEqual(Array.from(c.video[0].profiles),['baseline','high']);assert.equal(c.audio[0].max_channels,2);});
test('unknown profile and incomplete audio do not expand claims',()=>{const c=probe(JSON.stringify({profiles:['unknown'],fps:60,level:42,aac:false}));assert.equal(c.video.length,0);assert.equal(c.audio.length,0);});

test('null native response fails closed',()=>{const c=probe('null');assert.equal(c.video.length,0);});
