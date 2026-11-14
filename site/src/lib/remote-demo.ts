// "Try it" demo on the home page: a working copy of the TwinKeys Remote GO and Session screens and the
// Apple Watch app, with fictional data. Nothing here talks to a network. Every action is a pure function
// that returns a new state, so the page script only renders.

export type Mode = 'live' | 'qlab';
/** Live: GO and Session. QLab: GO and the cue list. */
export type Pane = 'go' | 'session' | 'list';
export type WatchPage = 0 | 1 | 2; // Live: GO, scene list, All Notes Off. QLab: GO, cue list, PANIC.

export interface Clip {
  has: boolean;
  name: string;
}

export interface DemoData {
  scenes: string[];
  tracks: string[];
  colors: string[];
  clips: Clip[][]; // [track][scene]
}

export interface DemoState {
  /** What the sample shows: Ableton Live (scenes and clips) or QLab (cues). */
  mode: Mode;
  /** QLab mode: the cue list, what runs, the playhead. */
  ql: QLabState;
  /** Scene that is playing (the GO screen's "Now playing"). */
  playing: number | null;
  /** Playing slot per track (null: stopped). */
  trackSlot: (number | null)[];
  /** Scene selected in Live: the one GO plays. */
  next: number;
  /** When the playing clips started (ms). */
  startedAt: number;
  /** Live's transport. */
  running: boolean;
  /** When the transport started, for the position (ms). */
  transportAt: number;
  locked: boolean;
  pane: Pane;
  watchPage: WatchPage;
  /** The main Mac in the demo: running or "stopped" by the visitor. */
  main: 'ok' | 'dead';
  lostAt: number | null;
  /** The iPhone moved to the backup Mac, which is now the main. */
  switched: boolean;
  /** Confirmation sheet for switching is open. */
  confirming: boolean;
  /** What both Macs just received (shown on the Mac cards). */
  lastEvent: { kind: EventKind; at: number; detail?: string } | null;
  /** Short message in the phone (and the watch), with the time it appeared. */
  notice: { kind: NoticeKind; at: number } | null;
  lastGoAt: number;
}

export type EventKind = 'go' | 'clip' | 'scene' | 'stopTrack' | 'select' | 'play' | 'stop' | 'notesOff' | 'playhead' | 'panic';
export type NoticeKind = 'notesOff' | 'unreachable' | 'stopHold' | 'unlockHold' | 'switched' | 'end' | 'panic' | 'stopped';

export const TEMPO = 124;
/** Every demo clip is 16 bars (64 beats) long and loops. */
export const CLIP_SECONDS = (64 * 60) / TEMPO;
/** A second GO within this time is ignored (as in the app). */
export const GO_GUARD_MS = 500;
/** The phone shows the red banner this long after the main Mac stops (as in the app). */
export const LOST_BANNER_MS = 3000;

export const COLORS = ['#E0533D', '#F0A030', '#3FA34D', '#2F7FD8', '#8E5CD6', '#D64F9A', '#E0533D', '#F0A030'];

export function demoData(sceneNames: string[]): DemoData {
  const tracks = ['Music', 'SE', 'Amb', 'Click', 'Pad', 'FX'];
  const clipNames = ['Intro', 'Applause', 'Pad', 'Count', 'Pad 2', 'Riser'];
  const clips = tracks.map((_, t) =>
    sceneNames.map((_, sc) => {
      const has = (sc * 3 + t) % 4 !== 3;
      return { has, name: has ? clipNames[t] : '' };
    }),
  );
  return { scenes: sceneNames, tracks, colors: COLORS, clips };
}

/** Scene 3 playing for a few seconds, scene 4 selected: the same picture as the app's screenshots.
 *  In QLab mode: 12 and the loop 11.5 running, 13 standing by (the app's QLab sample). */
export function initial(data: DemoData, now: number, mode: Mode = 'live'): DemoState {
  const st: DemoState = {
    mode,
    ql: qlabInitial(now),
    playing: null,
    trackSlot: data.tracks.map(() => null),
    next: 3,
    startedAt: now,
    running: true,
    transportAt: now - 5000,
    locked: false,
    pane: 'go',
    watchPage: 0,
    main: 'ok',
    lostAt: null,
    switched: false,
    confirming: false,
    lastEvent: null,
    notice: null,
    lastGoAt: 0,
  };
  const s = launchScene(data, st, 2, now - (CLIP_SECONDS - 26) * 1000);
  return { ...s, next: 3, lastEvent: null };
}

/** Commands reach Live only while the phone is linked to a running main Mac. */
export function reachable(s: DemoState): boolean {
  return s.main === 'ok' || s.switched;
}

function unreachable(s: DemoState, now: number): DemoState {
  return { ...s, notice: { kind: 'unreachable', at: now } };
}

function launchScene(data: DemoData, s: DemoState, sc: number, now: number): DemoState {
  const trackSlot = data.tracks.map((_, t) => (data.clips[t][sc].has ? sc : null));
  return { ...s, playing: sc, trackSlot, startedAt: now, running: true, transportAt: s.running ? s.transportAt : now };
}

export function go(data: DemoData, s: DemoState, now: number): DemoState {
  if (now - s.lastGoAt < GO_GUARD_MS) return s;
  if (!reachable(s)) return unreachable(s, now);
  if (s.next < 0 || s.next >= data.scenes.length) return { ...s, notice: { kind: 'end', at: now } };
  const sc = s.next;
  const n = launchScene(data, s, sc, now);
  return { ...n, next: Math.min(sc + 1, data.scenes.length), lastGoAt: now, lastEvent: { kind: 'go', at: now, detail: label(data, sc) } };
}

export function select(data: DemoData, s: DemoState, i: number, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  if (i < 0 || i >= data.scenes.length) return s;
  return { ...s, next: i, lastEvent: { kind: 'select', at: now, detail: label(data, i) } };
}

export function fireScene(data: DemoData, s: DemoState, sc: number, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  return { ...launchScene(data, s, sc, now), lastEvent: { kind: 'scene', at: now, detail: label(data, sc) } };
}

/** Tap a clip slot: a clip launches in its track; an empty slot stops the track (as in the app). */
export function tapSlot(data: DemoData, s: DemoState, t: number, sc: number, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  const trackSlot = [...s.trackSlot];
  if (!data.clips[t][sc].has) {
    trackSlot[t] = null;
    const playing = trackSlot.some((x) => x !== null) ? s.playing : null;
    return { ...s, trackSlot, playing, lastEvent: { kind: 'stopTrack', at: now, detail: data.tracks[t] } };
  }
  trackSlot[t] = sc;
  const others = trackSlot.some((x, k) => k !== t && x !== null);
  return {
    ...s,
    trackSlot,
    playing: s.playing ?? sc,
    startedAt: others ? s.startedAt : now,
    running: true,
    transportAt: s.running ? s.transportAt : now,
    lastEvent: { kind: 'clip', at: now, detail: `${data.tracks[t]} · ${data.clips[t][sc].name}` },
  };
}

export function play(s: DemoState, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  if (s.running) return s;
  return { ...s, running: true, transportAt: now, lastEvent: { kind: 'play', at: now } };
}

export function stop(data: DemoData, s: DemoState, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  return { ...s, running: false, playing: null, trackSlot: data.tracks.map(() => null), lastEvent: { kind: 'stop', at: now } };
}

export function allNotesOff(s: DemoState, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  return { ...s, lastEvent: { kind: 'notesOff', at: now }, notice: { kind: 'notesOff', at: now } };
}

export function hint(s: DemoState, kind: NoticeKind, now: number): DemoState {
  return { ...s, notice: { kind, at: now } };
}

export function setLock(s: DemoState, on: boolean): DemoState {
  return { ...s, locked: on };
}

export function setPane(s: DemoState, pane: Pane): DemoState {
  if (s.mode === 'live' ? pane === 'list' : pane === 'session') return s;
  return { ...s, pane };
}

/** Switching between Live and QLab starts the chosen one from the beginning. */
export function setMode(data: DemoData, s: DemoState, mode: Mode, now: number): DemoState {
  return s.mode === mode ? s : initial(data, now, mode);
}

export function setWatchPage(s: DemoState, page: WatchPage): DemoState {
  return { ...s, watchPage: page };
}

export function stopMain(s: DemoState, now: number): DemoState {
  if (s.main === 'dead') return s;
  return { ...s, main: 'dead', lostAt: now, switched: false, confirming: false };
}

export function askSwitch(s: DemoState): DemoState {
  return s.main === 'dead' && !s.switched ? { ...s, confirming: true } : s;
}

export function cancelSwitch(s: DemoState): DemoState {
  return { ...s, confirming: false };
}

export function switchToBackup(s: DemoState, now: number): DemoState {
  if (s.main !== 'dead' || s.switched) return s;
  return { ...s, switched: true, confirming: false, notice: { kind: 'switched', at: now } };
}

// MARK: Derived values for the screens

export function label(data: DemoData, sc: number): string {
  return `${sc + 1}  ${data.scenes[sc]}`;
}

/** Seconds left of the playing clip (clips loop, so this never stays at 0). */
export function secondsLeft(s: DemoState, now: number): number | null {
  if (s.playing === null || !s.running) return null;
  const t = Math.max(0, (now - s.startedAt) / 1000);
  return CLIP_SECONDS - (t % CLIP_SECONDS);
}

export function progress(s: DemoState, now: number): number {
  const left = secondsLeft(s, now);
  return left === null ? 0 : 1 - left / CLIP_SECONDS;
}

export function formatLeft(seconds: number): string {
  const v = Math.ceil(Math.max(0, seconds));
  return `-${Math.floor(v / 60)}:${String(v % 60).padStart(2, '0')}`;
}

/** Live's position as bars.beats.sixteenths (starts at 17.3.1 like the screenshots). */
export function position(s: DemoState, now: number): string {
  const beats = 66 + (s.running ? ((now - s.transportAt) / 1000) * (TEMPO / 60) : 0);
  const bar = Math.floor(beats / 4) + 1;
  const beat = Math.floor(beats % 4) + 1;
  const six = Math.floor((beats * 4) % 4) + 1;
  return `${bar}.${beat}.${six}`;
}

/** The red banner shows once the main Mac has been silent for 3 s. */
export function showsLostBanner(s: DemoState, now: number): boolean {
  return s.main === 'dead' && !s.switched && s.lostAt !== null && now - s.lostAt >= LOST_BANNER_MS;
}

export function lostSeconds(s: DemoState, now: number): number {
  return s.lostAt === null ? 0 : Math.floor((now - s.lostAt) / 1000);
}

/** Which Mac the phone talks to, for the top bar and the connection map. */
export function linkState(s: DemoState): 'ok' | 'dead' | 'switched' {
  if (s.main === 'ok') return 'ok';
  return s.switched ? 'switched' : 'dead';
}

export function visibleNotice(s: DemoState, now: number, ms = 3500): NoticeKind | null {
  return s.notice && now - s.notice.at < ms ? s.notice.kind : null;
}

export function recentEvent(s: DemoState, now: number, ms = 2500): DemoState['lastEvent'] {
  return s.lastEvent && now - s.lastEvent.at < ms ? s.lastEvent : null;
}

// MARK: QLab mode (the app's QLab sample: fictional workspace "sample-show", list "Main")

export type QCueType = 'memo' | 'audio' | 'fade' | 'group' | 'network';

export interface QCue {
  number: string;
  type: QCueType;
  /** Seconds (audio and fades); null: none (memo, group, network). */
  dur: number | null;
  /** A loop: plays until stopped; `dur` is one pass. */
  loop?: boolean;
  /** Inside a group (indented in the list). */
  depth: 0 | 1;
  /** A fade: the cue number it fades out (and stops at its end). */
  fades?: string;
}

/** The 16 cues of the app's QLab sample (iOS/Sources/RemoteModel.swift, loadDemoQLab). Names are in the texts. */
export const QCUES: QCue[] = [
  { number: '1', type: 'memo', dur: null, depth: 0 },
  { number: '2', type: 'audio', dur: 1080, depth: 0 },
  { number: '3', type: 'fade', dur: 8, depth: 0, fades: '2' },
  { number: '4', type: 'audio', dur: 6, depth: 0 },
  { number: '10', type: 'group', dur: null, depth: 0 },
  { number: '11', type: 'audio', dur: 90, depth: 1 },
  { number: '11.5', type: 'audio', dur: 300, loop: true, depth: 1 },
  { number: '12', type: 'audio', dur: 200, depth: 1 },
  { number: '13', type: 'audio', dur: 12, depth: 1 },
  { number: '14', type: 'fade', dur: 5, depth: 1, fades: '12' },
  { number: '15', type: 'network', dur: null, depth: 0 },
  { number: '20', type: 'group', dur: null, depth: 0 },
  { number: '21', type: 'audio', dur: 150, depth: 1 },
  { number: '22', type: 'audio', dur: 9, depth: 1 },
  { number: '23', type: 'fade', dur: 6, depth: 1, fades: '21' },
  { number: '90', type: 'audio', dur: 4, depth: 0 },
];

export const QTYPE_SHORT: Record<QCueType, string> = { memo: 'MEMO', audio: 'AUD', fade: 'FADE', group: 'GRP', network: 'NET' };

export interface QRun {
  /** Index into QCUES. */
  i: number;
  startedAt: number;
  /** When it stops by itself (ms); null: loops until stopped. */
  endsAt: number | null;
}

export interface QLabState {
  /** Index of the cue standing by (the playhead, the same on both Macs); null: past the end. */
  playhead: number | null;
  /** Cues started, newest last. Ended ones are dropped by the next action (see qRunning). */
  running: QRun[];
  /** The last GO: which cue, and whether both Macs took it. */
  last: { i: number; at: number } | null;
}

const qIndex = (n: string) => QCUES.findIndex((c) => c.number === n);

/** 12 Distant rain 1:03 from its end, the loop 11.5 under it, 13 standing by (as in the app's sample and the mockup). */
export function qlabInitial(now: number): QLabState {
  const i12 = qIndex('12'), i115 = qIndex('11.5');
  return {
    playhead: qIndex('13'),
    running: [
      { i: i115, startedAt: now - 385_000, endsAt: null },
      { i: i12, startedAt: now - 137_000, endsAt: now - 137_000 + 200_000 },
    ],
    last: { i: i12, at: now - 137_000 },
  };
}

/** Groups are never the playhead: the first cue at or after `i` (or before, going back) that is not a group. */
export function qPlayable(i: number, dir: 1 | -1 = 1): number | null {
  for (let k = i; k >= 0 && k < QCUES.length; k += dir) if (QCUES[k].type !== 'group') return k;
  return null;
}

/** Cues running at `now`, the newest first. */
export function qRunning(q: QLabState, now: number): QRun[] {
  return q.running.filter((r) => r.endsAt === null || r.endsAt > now).sort((a, b) => b.startedAt - a.startedAt);
}

/** The cue the GO screen shows as "Now playing": the newest running. */
export function qNow(q: QLabState, now: number): QRun | null {
  return qRunning(q, now)[0] ?? null;
}

/** Seconds left of a running cue (a loop counts down its pass and starts again). */
export function qLeft(r: QRun, now: number): number {
  const c = QCUES[r.i];
  const total = (r.endsAt === null ? (c.dur ?? 0) * 1000 : r.endsAt - r.startedAt) || 1;
  const t = Math.max(0, now - r.startedAt);
  return (r.endsAt === null ? total - (t % total) : Math.max(0, r.endsAt - now)) / 1000;
}

/** 0…1 of a running cue's length (for the bar). */
export function qProgress(r: QRun, now: number): number {
  const c = QCUES[r.i];
  const total = r.endsAt === null ? (c.dur ?? 0) : Math.max(0.001, (r.endsAt - r.startedAt) / 1000);
  return total > 0 ? Math.min(1, 1 - qLeft(r, now) / total) : 0;
}

/** A cue's length as the list shows it ("3:20", "0:12", "∞" for a loop, "" for none). */
export function qDuration(c: QCue): string {
  if (c.loop) return '∞';
  if (c.dur === null) return '';
  const v = Math.round(c.dur);
  return `${Math.floor(v / 60)}:${String(v % 60).padStart(2, '0')}`;
}

function withQ(s: DemoState, ql: QLabState, now: number): DemoState {
  return { ...s, ql: { ...ql, running: qRunning(ql, now) } };
}

/** GO: fires the cue standing by on both Macs and moves the playhead to the next cue (groups skipped).
 *  A second GO within 0.5 s is ignored (as in the app). */
export function qGo(names: string[], s: DemoState, now: number): DemoState {
  if (now - s.lastGoAt < GO_GUARD_MS) return s;
  if (!reachable(s)) return unreachable(s, now);
  const i = s.ql.playhead;
  if (i === null) return { ...s, notice: { kind: 'end', at: now } };
  const c = QCUES[i];
  let running = qRunning(s.ql, now).filter((r) => r.i !== i);
  if (c.type === 'fade' && c.fades !== undefined) {
    const target = qIndex(c.fades);
    const end = now + (c.dur ?? 0) * 1000;
    running = running.map((r) => (r.i === target && (r.endsAt === null || r.endsAt > end) ? { ...r, endsAt: end } : r));
  }
  // Memos and network cues happen at once; audio and fades run for their length.
  if (c.dur !== null) running = [...running, { i, startedAt: now, endsAt: c.loop ? null : now + c.dur * 1000 }];
  const ql: QLabState = { playhead: qPlayable(i + 1), running, last: { i, at: now } };
  return { ...withQ(s, ql, now), lastGoAt: now, lastEvent: { kind: 'go', at: now, detail: qLabel(names, i) } };
}

/** Moves the playhead on both Macs (list tap, ▲ Back / Next ▼, the watch). Never fires. */
export function qSetPlayhead(names: string[], s: DemoState, i: number, now: number, dir: 1 | -1 = 1): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  if (i < 0 || i >= QCUES.length) return s;
  const p = qPlayable(i, dir) ?? qPlayable(i, dir === 1 ? -1 : 1);
  if (p === null || p === s.ql.playhead) return s;
  return { ...withQ(s, { ...s.ql, playhead: p }, now), lastEvent: { kind: 'playhead', at: now, detail: qLabel(names, p) } };
}

export function qBack(names: string[], s: DemoState, now: number): DemoState {
  const from = s.ql.playhead ?? QCUES.length;
  return qSetPlayhead(names, s, from - 1, now, -1);
}

export function qNext(names: string[], s: DemoState, now: number): DemoState {
  if (s.ql.playhead === null) return s;
  return qSetPlayhead(names, s, s.ql.playhead + 1, now, 1);
}

/** PANIC (both Macs): everything stops. */
export function qPanic(s: DemoState, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  return { ...s, ql: { ...s.ql, running: [] }, lastEvent: { kind: 'panic', at: now }, notice: { kind: 'panic', at: now } };
}

/** STOP (long press, both Macs): everything stops at once. */
export function qStop(s: DemoState, now: number): DemoState {
  if (!reachable(s)) return unreachable(s, now);
  return { ...s, ql: { ...s.ql, running: [] }, lastEvent: { kind: 'stop', at: now }, notice: { kind: 'stopped', at: now } };
}

export function qLabel(names: string[], i: number): string {
  return `${QCUES[i].number}  ${names[i] ?? ''}`;
}
