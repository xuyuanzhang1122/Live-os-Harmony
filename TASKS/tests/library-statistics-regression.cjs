// 视频库大小与刷新回归：执行实际模型和 ViewModel，隔离平台 I/O。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const sdk = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(path.join(sdk, 'tools/hvigor/hvigor/node_modules/typescript'));
const root = path.resolve(__dirname, '../../entry/src/main/ets');
function load(file, modules = {}) {
  const exports = {};
  const source = fs.readFileSync(path.join(root, file), 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022}}).outputText,
    {exports, require: name => modules[name] || {}, console});
  return exports;
}
const {Formats} = load('common/Formats.ets');
const models = load('model/VideoLibrary.ets');
const library = load('viewmodel/VideoLibraryViewModel.ets', {'../model/VideoLibrary': models, '../common/Formats': {Formats}});
function room(fields = {}) {
  return new models.VideoRoomInfo({host_name: '主播', platform: '抖音', folder_path: '抖音/主播', video_count: 1,
    total_size: 188978561024, latest_video_at: 1, latest_video: 'a.flv', recording: false, url: null, ...fields});
}
const sizeText = value => library.videoLibrarySizeText?.(value) ?? Formats.formatBytes(value.total_size);
const rowKey = value => library.videoLibraryRoomKey?.(value) ?? value.roomId();
test('直接显示服务端下发的统计文本，不根据字节重新换算', () => {
  assert.equal(sizeText(room({total_size: 176, total_size_text: '189.0 GB', statistics_status: 'verified'})), '189.0 GB');
});
test('旧服务端原始字节按统一十进制显示', () => {
  assert.equal(sizeText(room()), '189.0 GB');
});
test('核验失败不显示部分大小或旧数字', () => {
  assert.equal(sizeText(room({statistics_status: 'unavailable', total_size_text: '176 GB'})), '统计暂不可用');
});
test('同一房间的大小、数量、封面与直播状态变化均更新卡片键', () => {
  const first = room(), original = rowKey(first);
  for (const fields of [{total_size: 200000000000}, {total_size_text: '200.0 GB'}, {video_count: 2},
    {latest_video: 'b.flv'}, {recording: true}, {host_name: '新名字'}, {statistics_status: 'unavailable'}]) {
    assert.notEqual(rowKey(room(fields)), original);
  }
});
test('保留缓存时也报告刷新失败，避免旧统计冒充当前值', async () => {
  const client = {baseURL: 'http://server', apiKey: '', getVideoLibrary: async () => {throw new Error('offline');}};
  const cache = {get: () => JSON.stringify([room()]), set: () => assert.fail('失败请求不能写入缓存')};
  const model = new library.VideoLibraryViewModel(client, cache);
  await model.load();
  assert.match(model.errorText, /offline/);
});
test('新请求替换缓存中的总大小，不在客户端累加', async () => {
  const next = room({total_size: 200000000000, total_size_text: '200.0 GB'}), writes = [];
  const client = {baseURL: 'http://server', apiKey: '', getVideoLibrary: async () => [next]};
  const cache = {get: () => JSON.stringify([room()]), set: (_key, data) => writes.push(JSON.parse(data))};
  const model = new library.VideoLibraryViewModel(client, cache);
  await model.load();
  assert.equal(model.rooms[0].total_size, 200000000000);
  assert.equal(writes[0][0].total_size, 200000000000);
});
