// Unit tests of the "Try it" demo's state (site/src/lib/remote-demo.ts). Run: npm test (Node's own test runner).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  demoData, initial, go, setMode, setPane, stopMain, switchToBackup, reachable, GO_GUARD_MS,
  QCUES, qRunning, qNow, qLeft, qGo, qSetPlayhead, qBack, qNext, qPanic, qStop, qDuration, qPlayable,
} from '../src/lib/remote-demo.ts';
import { demoText } from '../src/lib/remote-demo-text.ts';

const names = demoText.ja.q.cues;
const data = demoData(demoText.ja.scenes);
const T0 = 1_000_000;
const idx = (n: string) => QCUES.findIndex((c) => c.number === n);
const qlab = () => initial(data, T0, 'qlab');

test('the sample has the 16 cues of the app, with a name for each in both languages', () => {
  assert.equal(QCUES.length, 16);
  assert.equal(demoText.ja.q.cues.length, 16);
  assert.equal(demoText.en.q.cues.length, 16);
  assert.deepEqual(QCUES.map((c) => c.number), ['1', '2', '3', '4', '10', '11', '11.5', '12', '13', '14', '15', '20', '21', '22', '23', '90']);
});

test('Live stays the default and unchanged', () => {
  const s = initial(data, T0);
  assert.equal(s.mode, 'live');
  assert.equal(s.pane, 'go');
  assert.equal(s.playing, 2);
  assert.equal(s.next, 3);
  const n = go(data, s, T0 + 1000);
  assert.equal(n.playing, 3);
  assert.equal(n.next, 4);
});

test('QLab starts as in the app: 12 and the loop 11.5 running, 13 standing by', () => {
  const s = qlab();
  assert.equal(s.mode, 'qlab');
  assert.equal(s.ql.playhead, idx('13'));
  const run = qRunning(s.ql, T0);
  assert.deepEqual(run.map((r) => QCUES[r.i].number), ['12', '11.5']);
  assert.equal(QCUES[qNow(s.ql, T0)!.i].number, '12');
  assert.equal(Math.ceil(qLeft(run[0], T0)), 63); // -1:03
  assert.equal(Math.ceil(qLeft(run[1], T0)), 215); // -3:35 (a loop)
});

test('GO fires the cue standing by and moves the playhead on', () => {
  const s = qGo(names, qlab(), T0 + 1000);
  assert.equal(QCUES[qNow(s.ql, T0 + 1000)!.i].number, '13');
  assert.equal(s.ql.playhead, idx('14'));
  assert.equal(s.lastEvent?.kind, 'go');
  assert.equal(s.lastEvent?.detail, '13  雷鳴 1');
  assert.equal(s.ql.last?.i, idx('13'));
  // 13 is 12 s long: it ends by itself and 12 shows again.
  assert.equal(QCUES[qNow(s.ql, T0 + 14_000)!.i].number, '12');
});

test('a second GO within 0.5 s is ignored', () => {
  const a = qGo(names, qlab(), T0 + 1000);
  const b = qGo(names, a, T0 + 1000 + GO_GUARD_MS - 1);
  assert.equal(b, a);
  const c = qGo(names, a, T0 + 1000 + GO_GUARD_MS);
  assert.equal(c.ql.playhead, idx('15'));
});

test('a fade stops the cue it fades at its end', () => {
  let s = qlab();
  s = qGo(names, s, T0 + 1000); // 13
  s = qGo(names, s, T0 + 2000); // 14 fades 12 over 5 s
  const at = (ms: number) => qRunning(s.ql, ms).map((r) => QCUES[r.i].number);
  assert.ok(at(T0 + 6000).includes('12'));
  assert.ok(!at(T0 + 7001).includes('12'));
  assert.ok(at(T0 + 7001).includes('11.5'));
});

test('GO skips groups: after 15 the playhead goes to 21, not to the group 20', () => {
  let s = qSetPlayhead(names, qlab(), idx('15'), T0);
  s = qGo(names, s, T0 + 1000);
  assert.equal(s.ql.playhead, idx('21'));
});

test('tapping a cue moves the playhead without firing; a group moves it to its first cue', () => {
  const s0 = qlab();
  const s = qSetPlayhead(names, s0, idx('22'), T0 + 500);
  assert.equal(s.ql.playhead, idx('22'));
  assert.equal(qRunning(s.ql, T0 + 500).length, 2);
  assert.equal(s.lastEvent?.kind, 'playhead');
  assert.equal(qSetPlayhead(names, s0, idx('10'), T0).ql.playhead, idx('11'));
});

test('back and next move the playhead past groups', () => {
  let s = qSetPlayhead(names, qlab(), idx('11'), T0);
  s = qBack(names, s, T0);
  assert.equal(s.ql.playhead, idx('4'));
  s = qSetPlayhead(names, s, idx('15'), T0);
  s = qNext(names, s, T0);
  assert.equal(s.ql.playhead, idx('21'));
  assert.equal(qPlayable(QCUES.length), null);
});

test('after the last cue GO only says it is the end', () => {
  let s = qSetPlayhead(names, qlab(), idx('90'), T0);
  s = qGo(names, s, T0 + 1000);
  assert.equal(s.ql.playhead, null);
  const e = qGo(names, s, T0 + 2000);
  assert.equal(e.notice?.kind, 'end');
  assert.equal(qBack(names, s, T0 + 3000).ql.playhead, idx('90'));
});

test('PANIC and STOP stop everything on both Macs', () => {
  const p = qPanic(qlab(), T0 + 100);
  assert.equal(qRunning(p.ql, T0 + 100).length, 0);
  assert.equal(p.lastEvent?.kind, 'panic');
  assert.equal(p.ql.playhead, idx('13'));
  const st = qStop(qlab(), T0 + 100);
  assert.equal(qRunning(st.ql, T0 + 100).length, 0);
  assert.equal(st.lastEvent?.kind, 'stop');
});

test('stopping the main Mac: the backup keeps playing; commands wait for the switch', () => {
  let s = stopMain(qlab(), T0 + 100);
  assert.equal(reachable(s), false);
  assert.equal(qRunning(s.ql, T0 + 5000).length, 2);
  const blocked = qGo(names, s, T0 + 5000);
  assert.equal(blocked.notice?.kind, 'unreachable');
  assert.equal(blocked.ql.playhead, idx('13'));
  s = switchToBackup(s, T0 + 6000);
  s = qGo(names, s, T0 + 7000);
  assert.equal(s.ql.playhead, idx('14'));
});

test('switching modes starts the chosen one over; panes follow the mode', () => {
  let s = qGo(names, qlab(), T0 + 1000);
  s = setMode(data, s, 'live', T0 + 2000);
  assert.equal(s.mode, 'live');
  s = setMode(data, s, 'qlab', T0 + 3000);
  assert.equal(s.ql.playhead, idx('13'));
  assert.equal(setPane(s, 'list').pane, 'list');
  assert.equal(setPane(s, 'session').pane, 'go');
  assert.equal(setPane(initial(data, T0), 'list').pane, 'go');
});

test('durations as the list shows them', () => {
  assert.equal(qDuration(QCUES[idx('12')]), '3:20');
  assert.equal(qDuration(QCUES[idx('13')]), '0:12');
  assert.equal(qDuration(QCUES[idx('11.5')]), '∞');
  assert.equal(qDuration(QCUES[idx('10')]), '');
});
