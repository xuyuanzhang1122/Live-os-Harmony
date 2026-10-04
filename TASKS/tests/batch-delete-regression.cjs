// 执行实际 ETS 的网络解包与列表状态更新，平台装饰器仅在测试加载时移除。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../../entry/src/main/ets');
function load(file, dependencies) {
  const exports = {};
  const source = fs.readFileSync(path.join(root, file), 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022}}).outputText,
    {exports, require: name => dependencies[name] || {}, console});
  return exports;
}
const common = load('model/Common.ets', {});
let response;
const http = {RequestMethod: {POST: 'POST'}, createHttp: () => ({request: async () => {
  if (response instanceof Error) throw response;
  return {responseCode: 200, result: JSON.stringify(response)};
}, destroy() {}})};
const {APIClient} = load('net/APIClient.ets', {'@kit.NetworkKit': {http}, '../model/Common': common});
const {VideoListViewModel} = load('viewmodel/VideoLibraryViewModel.ets', {'../net/APIClient': {APIClient}});
function setup(data) {
  response = {err_no: 0, err_msg: '', data};
  const writes = [];
  const client = new APIClient('http://server', 'key', 'legacy');
  const model = new VideoListViewModel(client, 'room', '主播', {set: (key, value) => writes.push(JSON.parse(value))});
  model.files = [{rel_path: 'a'}, {rel_path: 'b'}, {rel_path: 'c'}];
  model.selectedPaths = ['a', 'b'];
  return {client, model, writes};
}
test('混合结果只移除成功项，保留失败选择、原因并同步缓存', async () => {
  const {model, writes} = setup([{path: 'a', success: true, message: '成功'}, {path: 'b', success: false, message: '正在录制'}]);
  assert.equal(await model.deleteSelected(), 1);
  assert.equal(JSON.stringify(model.files), '[{"rel_path":"b"},{"rel_path":"c"}]');
  assert.equal(JSON.stringify(model.selectedPaths), '["b"]');
  assert.match(model.deleteFailures[0].message, /正在录制/);
  assert.deepEqual(writes[0], [{rel_path: 'b'}, {rel_path: 'c'}]);
});
test('全部失败不移除文件且返回零', async () => {
  const {model} = setup([{path: 'a', success: false, message: '失败'}, {path: 'b', success: false, message: '失败'}]);
  assert.equal(await model.deleteSelected(), 0);
  assert.equal(model.files.length, 3);
  assert.equal(model.selectedPaths.length, 2);
});
test('请求失败保持文件和选中项且不写缓存', async () => {
  const {model, writes} = setup([]); response = new Error('offline');
  await assert.rejects(model.deleteSelected());
  assert.equal(model.files.length, 3); assert.equal(model.selectedPaths.length, 2); assert.equal(writes.length, 0);
});
for (const data of [null, {}, [{path: 'a', success: 'true'}], [{path: 'a', success: true}, {path: 'a', success: false}]]) {
  test(`非法结果不能伪报成功 ${JSON.stringify(data)}`, async () => {
    const {model} = setup(data);
    await assert.rejects(model.deleteSelected());
    assert.equal(model.files.length, 3);
  });
}
test('未返回的路径保留并提示，额外路径不能删除本地文件', async () => {
  const {model} = setup([{path: 'a', success: true, message: '成功'}, {path: 'c', success: true, message: '成功'}]);
  assert.equal(await model.deleteSelected(), 1);
  assert.equal(JSON.stringify(model.selectedPaths), '["b"]');
  assert.equal(model.deleteFailures[0].path, 'b');
  assert.equal(model.files.length, 2);
});
test('未经端点缺失确认的旧缓存不允许路径删除',async()=>{
 const {model,client}=setup([{path:'a',success:true}]);client.playbackAPI='auto';let called=0;
 client.batchDeleteFiles=async()=>{called++;return [{path:'a',success:true}];};
 await assert.rejects(model.deleteSelected(),/身份/);await assert.rejects(model.deleteFile(model.files[0]),/身份/);
 assert.equal(called,0);assert.equal(model.files.length,3);assert.deepEqual(Array.from(model.selectedPaths),['a','b']);
});
