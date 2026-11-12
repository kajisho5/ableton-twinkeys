// "Try it" demo on the home page: a working copy of the TwinKeys Remote GO and Session screens and the
// Apple Watch app, with fictional data. Nothing here talks to a network. Every action is a pure function
// that returns a new state, so the page script only renders.

export type Pane = 'go' | 'session';
export type WatchPage = 0 | 1 | 2; // GO, scene list, All Notes Off

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

export type EventKind = 'go' | 'clip' | 'scene' | 'stopTrack' | 'select' | 'play' | 'stop' | 'notesOff';
export type NoticeKind = 'notesOff' | 'unreachable' | 'stopHold' | 'unlockHold' | 'switched' | 'end';

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

/** Scene 3 playing for a few seconds, scene 4 selected: the same picture as the app's screenshots. */
export function initial(data: DemoData, now: number): DemoState {
  const st: DemoState = {
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
  return { ...s, pane };
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
