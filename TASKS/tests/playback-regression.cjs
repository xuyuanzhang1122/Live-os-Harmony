// 开发期回归：执行实际 ETS 源码，替换平台接口；真机验收不能由此替代。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const sdkHome = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(path.join(sdkHome, 'tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js'));
const root = path.resolve(__dirname, '../../entry/src/main/ets');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function load(source, requireStub, timers = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022
  }}).outputText, {exports, require: requireStub, setTimeout, clearTimeout, console, ...timers});
  return exports;
}
const common = load(fs.readFileSync(path.join(root, 'model/Common.ets'), 'utf8'), () => ({}));
const nativeErrors = [];
process.on('unhandledRejection', error => nativeErrors.push(error.message));
const controller = load(fs.readFileSync(path.join(root, 'player/PlayerController.ets'), 'utf8'),
  name => name === '@kit.PerformanceAnalysisKit' ? {hilog: {info() {}}} : {media: {}},
  {setTimeout: (fn, ms) => setTimeout(fn, ms === 30000 ? 35 : ms)});
class FakePlayer {
  constructor(mode) {this.mode = mode; this.state = 'idle'; this.duration = 120000;
    this.currentTime = 0; this.calls = []; this.sh = () => {}; this.eh = () => {};}
  set url(value) {this.state = 'initialized'; this.sh('initialized');}
  onStateChange(handler) {this.sh = handler;} offStateChange() {this.sh = () => {};}
  onError(handler) {this.eh = handler;} offError() {this.eh = () => {};}
  async prepare() {
    this.calls.push('prepare');
    if (this.mode === 'reject') throw new controller.PlayerOperationError(5400106, 'unsupported');
    if (this.mode === 'hang') return new Promise(() => {});
    if (this.mode === 'lateReject') return new Promise((resolve, reject) => {
      setTimeout(() => reject(new controller.PlayerOperationError(5400106, 'late')), 25);
    });
    if (this.mode === 'early') {setTimeout(() => this.emit('prepared'), 12); return;}
    if (this.mode === 'preparedHang') {this.emit('prepared'); return new Promise(() => {});}
    if (this.mode === 'noState') return;
    if (this.mode === 'stateError' || this.mode === 'errorState') {
      setTimeout(() => {
        if (this.mode === 'stateError') this.emit('error');
        this.eh(5400106, 'unsupported');
        if (this.mode === 'errorState') this.emit('error');
      }, 5);
      return;
    }
    this.emit('prepared');
  }
  emit(state) {this.state = state; this.sh(state);}
  async play() {this.calls.push('play'); this.emit('playing');}
  async pause() {} async stop() {this.calls.push('stop');}
  async reset() {} async release() {this.state = 'released';}
}
for (const event of ['SeekDone','DurationUpdate','VideoSizeChange','TimeUpdate','SpeedDone','VolumeChange','BufferingUpdate']) {
  FakePlayer.prototype['on' + event] = () => {};
  FakePlayer.prototype['off' + event] = () => {};
}
test('prepare 立即拒绝不产生游离的 prepared 拒绝', async () => {
  const c = new controller.PlayerController(async () => new FakePlayer('reject'));
  const before = nativeErrors.length; await c.setup('https://server/clip.mp4', 'surface'); await sleep(5);
  assert.deepEqual(nativeErrors.slice(before), []);
});
test('原生 prepare 挂起仍受整体准备期限约束', async () => {
  const player = new FakePlayer('hang'), c = new controller.PlayerController(async () => player);
  let ended = false; const task = c.setup('https://server/clip.mp4', 'surface').then(() => ended = true);
  await sleep(60); const timedOut = ended; await c.release(); await task;
  assert.equal(timedOut, true); assert.equal(player.calls.includes('play'), false);
});
for (const mode of ['hang', 'lateReject', 'preparedHang', 'noState']) {
  test(`退出取消 ${mode} 不播放、不产生未处理拒绝`, async () => {
    const player = new FakePlayer(mode), c = new controller.PlayerController(async () => player);
    const before = nativeErrors.length; const task = c.setup('https://server/clip.mp4', 'surface');
    await sleep(5); await c.release(); await task; await sleep(30);
    assert.equal(player.calls.includes('play'), false); assert.deepEqual(nativeErrors.slice(before), []);
  });
}
for (const mode of ['stateError', 'errorState']) {
  test(`异步错误 ${mode} 只回报一次原生错误码`, async () => {
    const c = new controller.PlayerController(async () => new FakePlayer(mode));
    const codes = []; c.onError = code => codes.push(code);
    await c.setup('https://server/clip.mp4', 'surface'); assert.deepEqual(codes, [5400106]);
  });
}
test('真实 prepared 之前不调用 play', async () => {
  const player = new FakePlayer('early'), c = new controller.PlayerController(async () => player);
  const task = c.setup('https://server/clip.mp4', 'surface'); await sleep(5);
  assert.equal(player.calls.includes('play'), false); await task;
  assert.equal(player.calls.includes('play'), true); await c.release();
});
let responseText = '';
const http = {RequestMethod: {GET: 'GET'}, createHttp: () => ({request: async () => ({responseCode: 200, result: responseText}), destroy() {}})};
const api = load(fs.readFileSync(path.join(root, 'net/APIClient.ets'), 'utf8'), name => {
  if (name === '@kit.NetworkKit') return {http};
  if (name.endsWith('/Common')) return common;
  if (name.endsWith('/VideoLibrary')) return {VideoFileInfo: {isNativePlayable: name => /\.(mp4|mov|m4v|ts)$/i.test(name)}};
  return {};
});
test('resolver 解包后返回带鉴权的绝对播放地址', async () => {
  responseText = JSON.stringify({err_no: 0, data: {status: 'ready', url: '/files/clip.mp4'}});
  const result = await new api.APIClient('https://server/proxy', 'key').resolvePlayback('clip.mp4');
  assert.equal(result.url, 'https://server/proxy/files/clip.mp4?_key=key');
});
test('签名播放地址原样保留签名且不追加 Key', async () => {
  responseText = JSON.stringify({err_no: 0, data: {status: 'ready', url: '/files/clip.mp4?expires=123&sig=abc'}});
  const result = await new api.APIClient('https://server', 'key').resolvePlayback('clip.mp4');
  assert.equal(result.url, 'https://server/files/clip.mp4?expires=123&sig=abc');
});
test('resolver 拒绝未知状态和缺少 URL 的 ready', async () => {
  const client = new api.APIClient('https://server');
  for (const data of [{status: 'unexpected'}, {status: 'ready'}]) {
    responseText = JSON.stringify({err_no: 0, data}); await assert.rejects(client.resolvePlayback('clip.mp4'));
  }
});
test('异常 retry 值回退到两秒', async () => {
  responseText = JSON.stringify({err_no: 0, data: {status: 'processing', retry_after_seconds: 'bad'}});
  assert.equal((await new api.APIClient('https://server').resolvePlayback('clip.flv')).retry_after_seconds, 2);
});
const pageSource = fs.readFileSync(path.join(root, 'pages/PlayerPage.ets'), 'utf8');
const pageMethods = pageSource.slice(pageSource.indexOf('  private async resolvePlaybackURL('), pageSource.indexOf('  private resolveURLs(')) +
  pageSource.slice(pageSource.indexOf('  private setupPlayer('), pageSource.indexOf('  private async togglePlayback('));
const page = load('export class PageProbe {' + pageMethods + '}', () => ({}), {
  APIClient: api.APIClient, ApiError: common.ApiError, ApiErrorType: common.ApiErrorType,
  playbackErrorText: () => '视频暂时无法播放', log() {}, delay: async () => {}
});
function pageProbe(error) {
  const calls = [], client = new api.APIClient('https://server'); client.resolvePlayback = async () => {throw error;};
  const probe = new page.PageProbe(); Object.assign(probe, {
    config: {getClient: () => client}, file: {rel_path: 'clip.flv', name: 'clip.flv', hls_url: null, file_url: null, thumbnail_url: null},
    resolveV2Playback: async () => false, isLifecycleActive: () => true, surfaceId: 'surface', playbackResolveTask: Promise.resolve(),
    shutdownStarted: false, setupStarted: false, errorText: '', controller: {setup: async url => calls.push(url)}
  }); return {probe, calls};
}
test('旧接口不可用时 fallback 启动已就绪 surface', async () => {
  const {probe, calls} = pageProbe(common.ApiError.server(404, '404 page not found'));
  await probe.resolvePlaybackURL(1); assert.equal(calls.length, 1);
  assert.equal(calls[0], 'https://server/api/stream/hls/clip.flv/playlist.m3u8');
});
test('契约错误和鉴权失败不被旧接口 fallback 吞掉', async () => {
  for (const error of [common.ApiError.decoding('未知状态'), common.ApiError.unauthorized()]) {
    const {probe, calls} = pageProbe(error); await probe.resolvePlaybackURL(1);
    assert.equal(calls.length, 0); assert.ok(probe.errorText.length > 0);
  }
});
test('URL 先就绪时 surface 后到只启动一次', async () => {
  const {probe, calls} = pageProbe(common.ApiError.server(404, '404 page not found'));
  probe.surfaceId = ''; await probe.resolvePlaybackURL(1); assert.equal(calls.length, 0);
  probe.setupPlayer('surface'); probe.setupPlayer('surface'); assert.equal(calls.length, 1);
});
test('旧会话晚到的状态和 Promise 不破坏新会话', async () => {
  const first = new FakePlayer('hang'), next = new FakePlayer('normal');
  let created = 0; const c = new controller.PlayerController(async () => ++created === 1 ? first : next);
  const oldTask = c.setup('https://server/first.mp4', 'surface'); await sleep(5);
  const lateState = first.sh, lateError = first.eh;
  await c.release(); await oldTask; await c.setup('https://server/next.mp4', 'surface');
  lateState('error'); lateError(5400106, 'stale');
  assert.equal(c.isPlaying, true); assert.deepEqual(next.calls, ['prepare', 'play']); await c.release();
});
test('旧会话的时间和时长回调不能污染新会话', async () => {
  FakePlayer.prototype.onDurationUpdate = function(handler) {this.dh = handler;};
  FakePlayer.prototype.offDurationUpdate = function() {this.dh = () => {};};
  FakePlayer.prototype.onTimeUpdate = function(handler) {this.th = handler;};
  FakePlayer.prototype.offTimeUpdate = function() {this.th = () => {};};
  const first = new FakePlayer('hang'), next = new FakePlayer('normal');
  let created = 0; const c = new controller.PlayerController(async () => ++created === 1 ? first : next);
  const task = c.setup('https://server/first.mp4', 'surface'); await sleep(5);
  const oldDuration = first.dh, oldTime = first.th;
  await c.release(); await task; await c.setup('https://server/next.mp4', 'surface');
  oldDuration(900000); oldTime(540000);
  assert.equal(c.duration, 120); assert.equal(c.currentTime, 0); await c.release();
});

const fixtures = JSON.parse(fs.readFileSync(path.resolve(__dirname,
  '../contracts/playback-resolve-fixtures.json'), 'utf8'));
for (const fixture of fixtures) {
  test(`共享服务端契约 ${fixture.name}`, async () => {
    responseText = JSON.stringify(fixture.response);
    const client = new api.APIClient('https://server/proxy/', 'secret');
    if (fixture.reject) { await assert.rejects(client.resolvePlayback('clip.flv')); return; }
    const result = await client.resolvePlayback('clip.flv');
    assert.equal(result.status, fixture.response.data.status);
    if (fixture.url) assert.equal(result.url, fixture.url);
    if (fixture.retry !== undefined) assert.equal(result.retry_after_seconds, fixture.retry);
  });
}
test('授权刷新在恢复seek倍速前不自动播放，暂停不会发声',async()=>{
 const player=new FakePlayer('normal');let seekDone;
 player.onSeekDone=h=>seekDone=h;player.offSeekDone=()=>{};
 player.seek=ms=>{player.calls.push('seek');player.currentTime=ms;setTimeout(()=>seekDone(ms),5);};
 player.setSpeed=rate=>player.calls.push('rate:'+rate);
 const c=new controller.PlayerController(async()=>player);
 await c.setup('https://server/refreshed.mp4','surface',{positionSeconds:45,rate:2,autoplay:false});
 assert.deepEqual(player.calls,['prepare','seek','rate:2']);assert.equal(c.currentTime,45);assert.equal(c.isPlaying,false);await c.release();
});
test('授权刷新恢复seek完成后才播放',async()=>{
 const player=new FakePlayer('normal');let seekDone;
 player.onSeekDone=h=>seekDone=h;player.offSeekDone=()=>{};
 player.seek=ms=>{player.calls.push('seek');setTimeout(()=>seekDone(ms),5);};player.setSpeed=()=>player.calls.push('rate');
 const c=new controller.PlayerController(async()=>player);
 await c.setup('https://server/refreshed.mp4','surface',{positionSeconds:30,rate:1.5,autoplay:true});
 assert.deepEqual(player.calls,['prepare','seek','rate','play']);await c.release();
});
test('HLS时长增长由当前会话更新，旧回调仍隔离',async()=>{
 const player=new FakePlayer('normal');player.onDurationUpdate=h=>player.dh=h;const c=new controller.PlayerController(async()=>player);
 await c.setup('https://server/index.m3u8','surface');player.dh(150000);assert.equal(c.duration,150);player.dh(180000);assert.equal(c.duration,180);await c.release();
});
test('首帧只认native事件并隔离退出后的晚到首帧',async()=>{
 const player=new FakePlayer('normal');let firstFrame;
 player.onFirstFrame=h=>firstFrame=h;player.offFirstFrame=()=>{};const c=new controller.PlayerController(async()=>player);
 let count=0;c.onFirstFrame=()=>count++;await c.setup('https://server/file.mp4','surface');assert.equal(count,0);
 assert.equal(typeof firstFrame,'function');firstFrame();assert.equal(count,1);await c.release();firstFrame();assert.equal(count,1);
});
