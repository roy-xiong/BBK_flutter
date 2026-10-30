/** 验证校准的真实状态机，不模拟浏览器已经读到了实体手柄。 */
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '..', 'gamepad_calibration.html'), 'utf8');
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(m => m[1]);
for (const source of scripts) new vm.Script(source);
const C = vm.runInNewContext(scripts[0] + '\nCalibrationCore;');
const device = { id: 'Controller (045e:028e)', mapping: 'standard', buttonCount: 17, axisCount: 6 };
const pad = (buttons = {}, axes = []) => ({
  buttons: Array.from({ length: 17 }, (_, i) => ({ value: buttons[i] ?? 0 })),
  axes: Array.from({ length: 6 }, (_, i) => axes[i] ?? 0),
});
const json = value => JSON.parse(JSON.stringify(value));

test('Xbox的25个位置身份唯一，包括两个摇杆8方向、十字键、双扳机', () => {
  assert.equal(C.controls.length, 25);
  assert.equal(new Set(C.controls.map(c => c[0])).size, 25);
  for (const id of ['a', 'b', 'lt', 'rt', 'lsUp', 'rsRight', 'dpadDown', 'l3', 'r3'])
    assert.ok(C.controls.some(c => c[0] === id));
});
test('只记录实体按下边沿，长按不连发，松开也不会覆盖候选信号', () => {
  const d = new C.Detector(); d.calibrate(pad());
  assert.deepEqual(json(d.sample(pad({ 0: 1 }))), [{ binding: { kind: 'button', index: 0 }, value: 1 }]);
  assert.equal(d.sample(pad({ 0: 1 })).length, 0);
  assert.equal(d.sample(pad()).length, 0);
  assert.equal(d.sample(pad({ 0: 1 })).length, 1);
});
test('唤醒网页时正按着的按键不被误当成首次校准', () => {
  const d = new C.Detector();
  assert.equal(d.sample(pad({ 0: 1 })).length, 0);
  d.sample(pad());
  assert.equal(d.sample(pad({ 0: 1 })).length, 1);
});
test('摇杆使用触发和释放两个阈值，漂移不会产生输入', () => {
  const d = new C.Detector(); d.calibrate(pad());
  for (const x of [.01, -.02, .2, -.3, .59]) assert.equal(d.sample(pad({}, [x])).length, 0);
  assert.equal(d.sample(pad({}, [.61]))[0].binding.sign, 1);
  assert.equal(d.sample(pad({}, [.4])).length, 0);
  d.sample(pad({}, [.27]));
  assert.equal(d.sample(pad({}, [.7])).length, 1);
});
test('左右、上下方向分别记录，正负轴不互相覆盖', () => {
  const d = new C.Detector(); d.calibrate(pad());
  const left = d.sample(pad({}, [-.9]))[0];
  const right = d.sample(pad({}, [.9]))[0];
  assert.notEqual(C.key(left.binding), C.key(right.binding));
  let bindings = C.assign({}, 'lsLeft', left.binding, device).bindings;
  bindings = C.assign(bindings, 'lsRight', right.binding, device).bindings;
  assert.equal(Object.keys(bindings).length, 2);
});
test('非标准扳机静止在-1时按完整行程归一化，不会一直显示按住', () => {
  const d = new C.Detector(); d.calibrate(pad({}, [0, 0, 0, 0, -1, 1]));
  assert.equal(d.sample(pad({}, [0, 0, 0, 0, -.5, .5])).length, 0);
  const found = d.sample(pad({}, [0, 0, 0, 0, .5, -.5]));
  assert.equal(found.length, 2);
  assert.equal(found[0].binding.sign, 1); assert.equal(found[0].binding.center, -1);
  assert.equal(found[1].binding.sign, -1); assert.equal(found[1].binding.center, 1);
});
test('方向斜推或重复报告同时到来时保留多个候选，不静默猜位置', () => {
  const d = new C.Detector(); d.calibrate(pad());
  const candidates = d.sample(pad({ 0: 1 }, [.8, -.9]));
  assert.equal(candidates.length, 3);
  assert.equal(candidates.filter(c => c.binding.kind === 'axis').length, 2);
});
test('同一原始信号改绑后只属于新位置，并返回原位置以供提示', () => {
  const result = C.assign({ a: { kind: 'button', index: 1 } }, 'b', { kind: 'button', index: 1 }, device);
  assert.deepEqual(json(result.bindings), { b: { kind: 'button', index: 1 } });
  assert.deepEqual(json(result.duplicates), ['a']);
});
test('导出再导入保留按钮、轴中位和键盘模式的对应关系', () => {
  let bindings = C.assign({}, 'a', { kind: 'button', index: 2 }, device).bindings;
  bindings = C.assign(bindings, 'lt', { kind: 'axis', index: 4, sign: 1, center: -1 }, device).bindings;
  bindings = C.assign(bindings, 'back', { kind: 'keyboard', code: 'Escape' }, device).bindings;
  const restored = C.sanitize({ documentType: 'bbk-gamepad-calibration', schema: 1, device, bindings });
  assert.deepEqual(json(restored.bindings), json(bindings));
  assert.equal(C.fingerprint(restored.device), C.fingerprint(device));
});
test('重连下标改变不改变设备身份；轴数、按键数或模式改变则区分配置', () => {
  assert.equal(C.fingerprint({ ...device, index: 0 }), C.fingerprint({ ...device, index: 1 }));
  for (const changed of [{ axisCount: 4 }, { buttonCount: 12 }, { mapping: '' }])
    assert.notEqual(C.fingerprint(device), C.fingerprint({ ...device, ...changed }));
});
test('不接受越界编号、NaN、未知位置或注入的按键代码', () => {
  const invalid = [
    ['a', { kind: 'button', index: 999 }], ['a', { kind: 'button', index: -1 }],
    ['a', { kind: 'axis', index: 0, sign: 0, center: 0 }],
    ['a', { kind: 'axis', index: 0, sign: 1, center: NaN }],
    ['__proto__', { kind: 'button', index: 0 }],
    ['a', { kind: 'keyboard', code: '<script>' }],
  ];
  for (const [id, binding] of invalid) assert.throws(() => C.assign({}, id, binding, device));
  const d = new C.Detector(); d.calibrate(pad());
  assert.equal(d.sample(pad({ 0: NaN }, [Infinity])).length, 0);
});
test('导入拒绝重复信号、错误schema、畸形设备、未知目标', () => {
  const value = { documentType: 'bbk-gamepad-calibration', schema: 1, device, bindings: {} };
  for (const changed of [
    { schema: 0 }, { device: { ...device, axisCount: -1 } },
    { bindings: { invalid: { kind: 'button', index: 0 } } },
    { bindings: { a: { kind: 'button', index: 0 }, b: { kind: 'button', index: 0 } } },
  ]) assert.throws(() => C.sanitize({ ...value, ...changed }));
});
