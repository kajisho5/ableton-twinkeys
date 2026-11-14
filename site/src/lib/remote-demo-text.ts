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
  backupPlaying: string;
  plan: string;
  deskTitle: string;
  deskMain: string;
  deskPlan: string;
  deskBackup: string;
  linkMainDesk: string;
  linkBackupDesk: string;
  // controls
  stopMain: string;
  reset: string;
  controlsNote1: string;
  controlsNote2: string;
  foot1: string;
  foot2: string;
  live: { go: string; select: string; switched: string; mainStopped: string; notesOff: string; reset: string };
  fallbackAlt: string;
  /** The Ableton Live | QLab switch above the sample. */
  modeLabel: string;
  modeHint: string;
  modeLive: string;
  /** QLab mode. */
  q: QLabText;
}

export interface QLabText {
  /** Names of the 16 sample cues, in the order of QCUES (remote-demo.ts). */
  cues: string[];
  workspace: string;
  runningCap: string;
  runningN: string;
  listCap: string;
  panic: string;
  panicAria: string;
  statusOk: string;
  nowPlaying: string;
  noneRunning: string;
  next: string;
  noneNext: string;
  backupToo: string;
  mainLost: string;
  left: string;
  back: string;
  fwd: string;
  playhead: string;
  stop: string;
  stopSub: string;
  stopAria: string;
  goCap: string;
  goSub: string;
  lastGo: string;
  lastGoLost: string;
  lastGoNone: string;
  goAria: string;
  listCount: string;
  search: string;
  follow: string;
  followAria: string;
  listHint: string;
  nextTag: string;
  noMatch: string;
  types: { memo: string; audio: string; fade: string; group: string; network: string };
  panes: { list: string; cues: string; go: string; settings: string };
  // watch
  watchDesc: string;
  watchPages: [string, string, string];
  chooseCue: string;
  lamps: string;
  lampsLost: string;
  // Macs and the map
  qlabOk: string;
  standby: string;
  nothingRunning: string;
  qlabMain: string;
  qlabBackup: string;
  thisMacOnly: string;
  qlabStopped: string;
  // controls and notes
  controlsNote1: string;
  foot1: string;
  foot2: string;
  notice: { panic: string; stopped: string; end: string };
  live: { go: string; playhead: string; panic: string; stopped: string; mode: string; modeLive: string };
  events: { playhead: string; panic: string; stop: string };
}

export const demoText: Record<Lang, DemoText> = {
  ja: {
    title: '触って試す',
    lead: '架空のデータで動く見本です。この画面は Mac にも Live・QLab にもつながっていません。',
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
      switched: '操作の届け先をバックアップに切り替えました',
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
    backupPlaying: '鳴り続けています',
    plan: '切り替えると、iPhone の操作がバックアップに直接届きます',
    deskTitle: '卓（Yamaha QL5）',
    deskMain: 'メインの音（Ch 1–4）',
    deskPlan: '切り替えると Ch 9–12 を上げます',
    deskBackup: 'バックアップの音（Ch 9–12）',
    linkMainDesk: '音 Ch 1–4 ・ LAN',
    linkBackupDesk: '音 Ch 9–12 ・ LAN',
    stopMain: 'メインの Mac を止めてみる',
    reset: 'はじめに戻す',
    controlsNote1: '止めても、バックアップの Mac はずっと鳴り続けます。iPhone には、操作の届け先を切り替える案内が出ます。',
    controlsNote2: '「バックアップに切り替える」→ 1 秒長押しで、アプリと同じ流れで切り替わります。',
    foot1: '見本で動くのは GO とセッション（クリップのます目）です。ミキサー・キュー・設定はアプリで使えます。',
    foot2: '音は鳴りません。代わりに、2台の Mac が同時に受け取ったことを表示します。',
    live: {
      go: 'シーン {x} を2台で再生しました',
      select: '次を {x} にしました',
      switched: '操作の届け先をバックアップに切り替えました',
      mainStopped: 'メインの Mac を止めました（バックアップは鳴り続けています）',
      notesOff: '全ノートオフを送りました',
      reset: 'はじめの状態に戻しました',
    },
    fallbackAlt:
      '横向きの iPhone の TwinKeys Remote。シーンとクリップの一覧、上に再生・停止・テンポ・全ノートオフ・本番ロック（架空のサンプル）。',
    modeLabel: '見本の対象',
    modeHint: '切り替えると、見本の中身が変わります',
    modeLive: 'Ableton Live',
    q: {
      cues: [
        '開演前の確認', '客入れ BGM', '客入れ BGM フェードアウト', '開演ベル', '第1場', '鳥の声（朝）',
        '夜の環境音（ループ）', '雨の音（遠く）', '雷鳴 1', '雨 フェードアウト', '映像へ合図', '第2場',
        '街のざわめき', '電話の音', 'ざわめき フェードアウト', '雷（予備）',
      ],
      workspace: 'ワークスペース',
      runningCap: '動いている',
      runningN: '{n} キュー',
      listCap: 'リスト',
      panic: 'PANIC（2台）',
      panicAria: 'PANIC：2台の QLab を止める',
      statusOk: 'バックアップ ✓ · QLab ✓ · 2 ms',
      nowPlaying: 'いま鳴っている',
      noneRunning: '動いているキューはありません',
      next: '次',
      noneNext: '待機中のキューはありません',
      backupToo: 'バックアップも {n} で待機中',
      mainLost: 'メインの Mac が応答しません',
      left: '残り',
      back: '▲ 前へ',
      fwd: '次へ ▼',
      playhead: '再生位置（2台）',
      stop: 'STOP',
      stopSub: '長押し',
      stopAria: '2台とも停止（長押し）',
      goCap: 'QLAB',
      goSub: '次のキューを鳴らす',
      lastGo: '直前の GO：{x} メイン ✓ バックアップ ✓',
      lastGoLost: '直前の GO：{x} バックアップ ✓',
      lastGoNone: '直前の GO：まだありません',
      goAria: 'GO：QLab のキュー {x}',
      listCount: '{n} キュー',
      search: '番号か名前で探す',
      follow: '追従',
      followAria: '再生位置に付いていく',
      listHint: 'タップで2台の再生位置をそこへ移します（鳴らしません）',
      nextTag: '次',
      noMatch: '見つかりません',
      types: { memo: 'メモ', audio: 'オーディオ', fade: 'フェード', group: 'グループ', network: 'ネットワーク' },
      panes: { list: '一覧', cues: 'キュー', go: 'GO', settings: '設定' },
      watchDesc: 'GO・キューの一覧・PANIC',
      watchPages: ['GO', 'キューの一覧', 'PANIC'],
      chooseCue: 'キューを選ぶ',
      lamps: 'メイン ✓ · バックアップ ✓',
      lampsLost: 'メイン ✗',
      qlabOk: 'QLab ✓',
      standby: '待機：{x}',
      nothingRunning: '■ 動いているキューはありません',
      qlabMain: 'QLab（メイン）',
      qlabBackup: 'QLab（バックアップ）',
      thisMacOnly: 'この Mac の中だけ',
      qlabStopped: '止まっています',
      controlsNote1: '止めても、バックアップの Mac の QLab はずっと鳴り続けます。iPhone には、操作の届け先を切り替える案内が出ます。',
      foot1: '見本で動くのは GO と一覧です。キューのキー・設定はアプリで使えます。',
      foot2: '音は鳴りません。代わりに、2台の QLab が同時に受け取ったことを表示します。',
      notice: { panic: 'PANIC を2台に送りました', stopped: 'STOP を2台に送りました', end: 'キューの最後です' },
      live: {
        go: '{x} を2台の QLab で鳴らしました',
        playhead: '次を {x} にしました',
        panic: 'PANIC を送りました。2台とも止まりました',
        stopped: '2台とも止めました',
        mode: 'QLab の見本に切り替えました',
        modeLive: 'Ableton Live の見本に切り替えました',
      },
      events: { playhead: '再生位置', panic: 'PANIC', stop: 'STOP' },
    },
  },
  en: {
    title: 'Try it',
    lead: 'A working sample with made-up data. This page is not connected to any Mac, to Live or to QLab.',
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
      switched: 'The iPhone now controls the backup',
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
    backupPlaying: 'Still playing',
    plan: 'Switching sends the iPhone\'s controls straight to the backup',
    deskTitle: 'Console (Yamaha QL5)',
    deskMain: "Main's sound (Ch 1–4)",
    deskPlan: 'Switching raises Ch 9–12',
    deskBackup: "Backup's sound (Ch 9–12)",
    linkMainDesk: 'Sound Ch 1–4 · LAN',
    linkBackupDesk: 'Sound Ch 9–12 · LAN',
    stopMain: 'Stop the main Mac',
    reset: 'Start over',
    controlsNote1: 'Stop it: the backup Mac keeps playing all along. The iPhone offers to send its controls to the backup.',
    controlsNote2: '"Switch to the backup", then hold for 1 second: the same steps as in the app.',
    foot1: 'GO and Session (the clip grid) work in this sample. Mixer, Cues and Settings work in the app.',
    foot2: 'No sound plays. Instead you see both Macs receive each action at the same time.',
    live: {
      go: 'Scene {x} played on both Macs',
      select: 'Next is now {x}',
      switched: 'The iPhone now controls the backup',
      mainStopped: 'The main Mac was stopped (the backup keeps playing)',
      notesOff: 'All Notes Off sent',
      reset: 'Back to the start',
    },
    fallbackAlt:
      'TwinKeys Remote on an iPhone held sideways: the session grid of scenes and clips, with play, stop, tempo, All Notes Off and the show lock along the top (sample data).',
    modeLabel: 'Sample for',
    modeHint: 'Switching changes what the sample shows',
    modeLive: 'Ableton Live',
    q: {
      cues: [
        'Pre-show check', 'House music', 'House music fade out', 'Show bell', 'Scene 1', 'Birds (morning)',
        'Night ambience (loop)', 'Distant rain', 'Thunder 1', 'Rain fade out', 'Cue to video', 'Scene 2',
        'Street crowd', 'Phone ring', 'Crowd fade out', 'Thunder (spare)',
      ],
      workspace: 'Workspace',
      runningCap: 'Running',
      runningN: '{n} cues',
      listCap: 'List',
      panic: 'PANIC (both)',
      panicAria: 'PANIC: stop QLab on both Macs',
      statusOk: 'Backup ✓ · QLab ✓ · 2 ms',
      nowPlaying: 'Now playing',
      noneRunning: 'No cue running',
      next: 'Next · standing by',
      noneNext: 'Nothing standing by',
      backupToo: 'Backup standing by on {n} too',
      mainLost: 'The main Mac is not answering',
      left: 'Left',
      back: '▲ Back',
      fwd: 'Next ▼',
      playhead: 'Playhead (both)',
      stop: 'STOP',
      stopSub: 'Hold',
      stopAria: 'Stop on both Macs (hold)',
      goCap: 'QLAB',
      goSub: 'Fire the next cue',
      lastGo: 'Last GO: {x} · main ✓ backup ✓',
      lastGoLost: 'Last GO: {x} · backup ✓',
      lastGoNone: 'Last GO: none yet',
      goAria: 'GO: QLab cue {x}',
      listCount: '{n} cues',
      search: 'Find a number or name',
      follow: 'Follow',
      followAria: 'Follow the playhead',
      listHint: 'Tap to move the playhead on both Macs there (does not fire)',
      nextTag: 'next',
      noMatch: 'No match',
      types: { memo: 'Memo', audio: 'Audio', fade: 'Fade', group: 'Group', network: 'Network' },
      panes: { list: 'List', cues: 'Cues', go: 'GO', settings: 'Settings' },
      watchDesc: 'GO, cue list, PANIC',
      watchPages: ['GO', 'Cue list', 'PANIC'],
      chooseCue: 'Choose cue',
      lamps: 'Main ✓ · Backup ✓',
      lampsLost: 'Main ✗',
      qlabOk: 'QLab ✓',
      standby: 'Standing by: {x}',
      nothingRunning: '■ No cue running',
      qlabMain: 'QLab (main)',
      qlabBackup: 'QLab (backup)',
      thisMacOnly: 'Inside this Mac only',
      qlabStopped: 'Stopped',
      controlsNote1: "Stop it: QLab on the backup Mac keeps playing all along. The iPhone offers to send its controls to the backup.",
      foot1: 'GO and the cue list work in this sample. Cue keys and Settings work in the app.',
      foot2: 'No sound plays. Instead you see both QLabs receive each action at the same time.',
      notice: { panic: 'PANIC sent to both Macs', stopped: 'STOP sent to both Macs', end: 'End of the cue list' },
      live: {
        go: '{x} fired on both QLabs',
        playhead: 'Next is now {x}',
        panic: 'PANIC sent: both stopped',
        stopped: 'Both stopped',
        mode: 'Now showing the QLab sample',
        modeLive: 'Now showing the Ableton Live sample',
      },
      events: { playhead: 'playhead', panic: 'PANIC', stop: 'STOP' },
    },
  },
};
