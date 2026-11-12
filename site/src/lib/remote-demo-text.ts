import type { Lang } from './i18n';

/** Texts of the "Try it" demo. `{n}`, `{name}` and `{x}` are filled in by the page script. */
export interface DemoText {
  title: string;
  lead: string;
  scenes: string[];
  // phone
  nowPlaying: string;
  next: string;
  left: string;
  nothingPlaying: string;
  endOfList: string;
  goSub: string;
  goLock: string;
  back: string;
  fwd: string;
  chooseOnly: string;
  allNotesOff: string;
  play: string;
  stop: string;
  lock: string;
  unlock: string;
  panes: { session: string; mixer: string; cues: string; go: string; settings: string };
  paneOff: string;
  sceneHeader: string;
  launchScene: string;
  stopTrack: string;
  statusOk: string;
  statusLost: string;
  statusSwitched: string;
  lostBanner: string;
  switchButton: string;
  confirmTitle: string;
  confirmBody: string;
  confirmPhone: string;
  confirmKeys: string;
  cancel: string;
  hold: string;
  holdSecond: string;
  switchedBanner: string;
  notice: { notesOff: string; unreachable: string; stopHold: string; unlockHold: string; switched: string; end: string };
  // watch
  watchTitle: string;
  watchDesc: string;
  watchHint: string;
  watchNext: string;
  crownHint: string;
  crownBack: string;
  crownNext: string;
  crownNote: string;
  watchPages: [string, string, string];
  chooseScene: string;
  tapChoose: string;
  watchLinks: string;
  watchLinksLost: string;
  lastCue: string;
  lastCueNone: string;
  // Macs
  mainMac: string;
  backupMac: string;
  liveOk: string;
  noAnswer: string;
  stoppedNote: string;
  mainBadge: string;
  stoppedLine: string;
  received: string;
  events: { go: string; clip: string; scene: string; stopTrack: string; select: string; play: string; stop: string; notesOff: string };
  // connection map
  mapTitle: string;
  watchLinked: string;
  phoneToMain: string;
  phoneLost: string;
  phoneToBackup: string;
  linkWatch: string;
  linkPhone: string;
  direct: string;
  viaMain: string;
  liveReceived: string;
  backupUnreached: string;
  plan: string;
  // controls
  stopMain: string;
  reset: string;
  controlsNote1: string;
  controlsNote2: string;
  foot1: string;
  foot2: string;
  live: { go: string; select: string; switched: string; mainStopped: string; notesOff: string; reset: string };
  fallbackAlt: string;
}

export const demoText: Record<Lang, DemoText> = {
  ja: {
    title: '触って試す',
    lead: '架空のデータで動く見本です。この画面は Mac にも Live にもつながっていません。',
    scenes: ['オープニング', 'SE 拍手', 'M1 イントロ', 'M1 本編', '暗転', 'M2 イントロ', 'M2 本編', 'エンディング'],
    nowPlaying: 'いま再生中',
    next: '次',
    left: '残り',
    nothingPlaying: '再生中のシーンはありません',
    endOfList: 'シーンの最後です',
    goSub: '次のシーンを再生',
    goLock: '本番ロック中も使えます',
    back: '◀ 前へ',
    fwd: '次へ ▶',
    chooseOnly: '選ぶだけ（鳴らさない）',
    allNotesOff: '全ノートオフ',
    play: '再生',
    stop: '停止（長押し）',
    lock: '本番ロック',
    unlock: '本番ロック中（解除は 1 秒長押し）',
    panes: { session: 'セッション', mixer: 'ミキサー', cues: 'キュー', go: 'GO', settings: '設定' },
    paneOff: '見本では使えません（アプリで使えます）',
    sceneHeader: 'シーン',
    launchScene: 'シーン {n} を再生',
    stopTrack: '{x} を停止',
    statusOk: 'バックアップ ✓ · Live ✓ · 2 ms',
    statusLost: 'メイン切断中',
    statusSwitched: 'バックアップ未接続',
    lostBanner: '⚠ メインの Mac が応答しません（{n} 秒）',
    switchButton: 'バックアップに切り替える',
    confirmTitle: 'バックアップに切り替えますか？',
    confirmBody: '{name} がメインになります。',
    confirmPhone: '・iPhone は {name} につなぎ直します',
    confirmKeys: '・{name} のキーボードでキューを出せるようになります',
    cancel: 'やめる',
    hold: '長押しで切り替え',
    holdSecond: '1 秒',
    switchedBanner: 'バックアップに切り替えました：{name} がメインです',
    notice: {
      notesOff: '全ノートオフを2台に送りました',
      unreachable: '届きません：メインの Mac が応答しません',
      stopHold: '停止は長押しです',
      unlockHold: '解除は鍵を 1 秒長押しします',
      switched: 'バックアップに切り替えました',
      end: 'シーンの最後です',
    },
    watchTitle: 'Apple Watch',
    watchDesc: 'GO・シーンを選ぶ・全ノートオフ',
    watchHint: '点を押すと画面が切り替わります',
    watchNext: '次：{x}',
    crownHint: 'クラウンで前・次',
    crownBack: '▲ 前',
    crownNext: '次 ▼',
    crownNote: '（クラウンの代わり）',
    watchPages: ['GO', 'シーンを選ぶ', '全ノートオフ'],
    chooseScene: 'シーンを選ぶ',
    tapChoose: 'タップで「次」に選ぶ（鳴らさない）',
    watchLinks: 'メイン ✓ · バックアップ ✓',
    watchLinksLost: 'メイン ✗',
    lastCue: '直前：{x} ✓',
    lastCueNone: '直前：まだありません',
    mainMac: 'Main Stage Mac',
    backupMac: 'Backup Stage Mac',
    liveOk: 'Live ✓',
    noAnswer: '応答なし',
    stoppedNote: '（見本で止めています）',
    mainBadge: 'メイン',
    stoppedLine: '■ 停止中',
    received: '↓ {x} を受け取りました · 2 ms',
    events: { go: 'GO', clip: 'クリップ', scene: 'シーン', stopTrack: 'トラック停止', select: '選択', play: '再生', stop: '停止', notesOff: '全ノートオフ' },
    mapTitle: 'つながり',
    watchLinked: 'つながっています',
    phoneToMain: 'メインに接続中',
    phoneLost: 'メイン切断中',
    phoneToBackup: 'バックアップに接続中',
    linkWatch: 'Bluetooth / Wi-Fi',
    linkPhone: 'Wi-Fi',
    direct: '直接',
    viaMain: 'メイン経由（LAN）',
    liveReceived: 'Live ✓ · 受け取り 2 ms',
    backupUnreached: 'Live ✓（いまは iPhone から届かない）',
    plan: '切り替えると、iPhone はバックアップに直接つなぎ直します',
    stopMain: 'メインの Mac を止めてみる',
    reset: 'はじめに戻す',
    controlsNote1: '止めると、iPhone に切り替えの案内が出ます。',
    controlsNote2: '「バックアップに切り替える」→ 1 秒長押しで、アプリと同じ流れで切り替わります。',
    foot1: '見本で動くのは GO とセッション（クリップのます目）です。ミキサー・キュー・設定はアプリで使えます。',
    foot2: '音は鳴りません。代わりに、2台の Mac が同時に受け取ったことを表示します。',
    live: {
      go: 'シーン {x} を2台で再生しました',
      select: '次を {x} にしました',
      switched: 'バックアップに切り替えました',
      mainStopped: 'メインの Mac を止めました',
      notesOff: '全ノートオフを送りました',
      reset: 'はじめの状態に戻しました',
    },
    fallbackAlt:
      '横向きの iPhone の TwinKeys Remote。シーンとクリップの一覧、上に再生・停止・テンポ・全ノートオフ・本番ロック（架空のサンプル）。',
  },
  en: {
    title: 'Try it',
    lead: 'A working sample with made-up data. This page is not connected to any Mac or to Live.',
    scenes: ['Opening', 'SE Applause', 'M1 Intro', 'M1 Main', 'Blackout', 'M2 Intro', 'M2 Main', 'Ending'],
    nowPlaying: 'Now playing',
    next: 'Next',
    left: 'Left',
    nothingPlaying: 'Nothing playing',
    endOfList: 'End of the scene list',
    goSub: 'Play the next scene',
    goLock: 'Works with the show lock on',
    back: '◀ Back',
    fwd: 'Next ▶',
    chooseOnly: 'Only chooses (does not play)',
    allNotesOff: 'All Notes Off',
    play: 'Play',
    stop: 'Stop (hold)',
    lock: 'Show lock',
    unlock: 'Show lock on (hold 1 s to unlock)',
    panes: { session: 'Session', mixer: 'Mixer', cues: 'Cues', go: 'GO', settings: 'Settings' },
    paneOff: 'Not in this sample (works in the app)',
    sceneHeader: 'Scene',
    launchScene: 'Launch scene {n}',
    stopTrack: 'Stop {x}',
    statusOk: 'Backup ✓ · Live ✓ · 2 ms',
    statusLost: 'Main Mac: no answer',
    statusSwitched: 'Backup not linked',
    lostBanner: '⚠ The main Mac is not answering ({n} s)',
    switchButton: 'Switch to the backup',
    confirmTitle: 'Switch to the backup?',
    confirmBody: '{name} becomes the main.',
    confirmPhone: '· The iPhone connects to {name}',
    confirmKeys: "· {name}'s keyboard fires the cues",
    cancel: 'Cancel',
    hold: 'Hold to switch',
    holdSecond: '1 s',
    switchedBanner: 'Switched to the backup: {name} is the main',
    notice: {
      notesOff: 'All Notes Off sent to both Macs',
      unreachable: 'Not sent: the main Mac is not answering',
      stopHold: 'Stop needs a long press',
      unlockHold: 'Hold the lock for 1 second to unlock',
      switched: 'Switched to the backup',
      end: 'End of the scene list',
    },
    watchTitle: 'Apple Watch',
    watchDesc: 'GO, choose scene, All Notes Off',
    watchHint: 'Tap the dots to change pages',
    watchNext: 'Next: {x}',
    crownHint: 'Digital Crown: back / next',
    crownBack: '▲ Back',
    crownNext: 'Next ▼',
    crownNote: '(instead of the Digital Crown)',
    watchPages: ['GO', 'Choose scene', 'All Notes Off'],
    chooseScene: 'Choose scene',
    tapChoose: 'Tap to make it Next (does not play)',
    watchLinks: 'Main ✓ · Backup ✓',
    watchLinksLost: 'Main ✗',
    lastCue: 'Last: {x} ✓',
    lastCueNone: 'Last cue: none yet',
    mainMac: 'Main Stage Mac',
    backupMac: 'Backup Stage Mac',
    liveOk: 'Live ✓',
    noAnswer: 'No answer',
    stoppedNote: '(stopped in this sample)',
    mainBadge: 'Main',
    stoppedLine: '■ Stopped',
    received: '↓ Received {x} · 2 ms',
    events: { go: 'GO', clip: 'clip', scene: 'scene', stopTrack: 'track stop', select: 'selection', play: 'play', stop: 'stop', notesOff: 'All Notes Off' },
    mapTitle: 'Connections',
    watchLinked: 'Connected',
    phoneToMain: 'Connected to the main',
    phoneLost: 'Main Mac: no answer',
    phoneToBackup: 'Connected to the backup',
    linkWatch: 'Bluetooth / Wi-Fi',
    linkPhone: 'Wi-Fi',
    direct: 'Direct',
    viaMain: 'Via the main (LAN)',
    liveReceived: 'Live ✓ · received in 2 ms',
    backupUnreached: 'Live ✓ (the iPhone cannot reach it now)',
    plan: 'Switching connects the iPhone straight to the backup',
    stopMain: 'Stop the main Mac',
    reset: 'Start over',
    controlsNote1: 'Stop it and the iPhone offers to switch.',
    controlsNote2: '"Switch to the backup", then hold for 1 second: the same steps as in the app.',
    foot1: 'GO and Session (the clip grid) work in this sample. Mixer, Cues and Settings work in the app.',
    foot2: 'No sound plays. Instead you see both Macs receive each action at the same time.',
    live: {
      go: 'Scene {x} played on both Macs',
      select: 'Next is now {x}',
      switched: 'Switched to the backup',
      mainStopped: 'The main Mac was stopped',
      notesOff: 'All Notes Off sent',
      reset: 'Back to the start',
    },
    fallbackAlt:
      'TwinKeys Remote on an iPhone held sideways: the session grid of scenes and clips, with play, stop, tempo, All Notes Off and the show lock along the top (sample data).',
  },
};
