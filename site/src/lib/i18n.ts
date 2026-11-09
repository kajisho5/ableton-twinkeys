export type Lang = 'en' | 'ja';

export const REPO_URL = 'https://github.com/kajisho5/ableton-twinkeys';
export const DOWNLOAD_URL = `${REPO_URL}/releases/latest`;
export const LICENSE_URL = `${REPO_URL}/blob/main/LICENSE`;

/** Joins a site-relative path onto the configured base, e.g. url('ja/') -> /ableton-twinkeys/ja/ */
export function url(path = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  const clean = path.replace(/^\//, '');
  return `${base}/${clean}`;
}

/** Page key -> path without language prefix. */
export type PageKey = 'home' | 'guide' | 'releases';
const PATHS: Record<PageKey, string> = { home: '', guide: 'guide/', releases: 'releases/' };

export function pageUrl(lang: Lang, page: PageKey): string {
  return url((lang === 'ja' ? 'ja/' : '') + PATHS[page]);
}

export const t = {
  en: {
    htmlLang: 'en',
    switchLabel: '日本語',
    switchLang: 'ja' as Lang,
    switchHreflang: 'ja',
    navGuide: 'Guide',
    navReleases: 'Release notes',
    navDownload: 'Download',
    navMenu: 'Menu',
    siteDescription:
      'TwinKeys fires your Ableton Live sound cues on a main and a backup Mac at once. Free, open source, notarized by Apple.',
    homeTitle: 'TwinKeys — One cue. Two Macs. At once.',
    heroTitle: ['One cue.', 'Two Macs. At once.'],
    heroLead: ['Fire a cue on the main Mac and the backup Mac fires it too.', 'If the main Mac fails, switch over straight away.'],
    download: (v: string) => `Download ${v}`,
    readGuide: 'Read the guide',
    metaLong: 'macOS 13 or later · Apple silicon and Intel · Free (MIT)',
    metaShort: 'macOS 13+ · Free (MIT) · Notarized',
    notarized: 'Notarized by Apple. Unofficial third-party tool.',
    screenshotAlt:
      'The TwinKeys window: connected to Backup Stage Mac with 2 ms latency, a list of nearby Macs, and the key and note settings.',
    howTitle: 'How it works',
    how: [
      ['Main Mac', 'Keys → TwinKeys'],
      ['Network', 'Encrypted with a pairing code'],
      ['Backup Mac', 'TwinKeys → Live'],
    ],
    howNote: 'The main Mac’s Live also receives every cue from the TwinKeys MIDI port.',
    featuresTitle: 'Features',
    features: [
      ['Fires on both', 'Each key launches the same clip in both Lives'],
      ['Reconnects itself', 'When the network comes back, so does the link'],
      ['All Notes Off', 'One button stops every note on both Macs'],
      ['Pairing code', 'Only your Macs connect, and traffic is encrypted'],
      ['Delivery check', 'A ✓ shows each cue reached the backup'],
      ['English and Japanese', 'App and guide in both languages'],
    ],
    stepsTitle: 'Get started',
    steps: ['Install on both Macs', 'Set the same pairing code', 'Turn on TwinKeys in Live', 'Click Connect'],
    stepsMore: 'Step-by-step instructions are in the guide.',
    guideTitle: 'Guide',
    guideDocTitle: 'Using TwinKeys — TwinKeys Guide',
    releasesTitle: 'Release notes',
    releasesDocTitle: 'Release notes — TwinKeys',
    releasesLead: 'What is new and what was fixed in each version.',
    latest: 'Latest',
    footerMade: 'Made by Shogo Kajiyama / SEVENTHWELL',
    footerLicense: 'MIT License',
    footerTrademark:
      'TwinKeys is an unofficial third-party tool. Ableton and Live are trademarks of Ableton AG.',
    skip: 'Skip to content',
  },
  ja: {
    htmlLang: 'ja',
    switchLabel: 'English',
    switchLang: 'en' as Lang,
    switchHreflang: 'en',
    navGuide: '使い方',
    navReleases: 'リリースノート',
    navDownload: 'ダウンロード',
    navMenu: 'メニュー',
    siteDescription:
      'TwinKeys は、メインの Mac で叩いたキューをバックアップの Mac の Ableton Live でも同時に再生する無料のツールです。Apple の公証済み。',
    homeTitle: 'TwinKeys — キューを叩けば、2台の Mac で同時に。',
    heroTitle: ['キューを叩けば、', '2台の Mac で同時に。'],
    heroLead: [
      'メインの Mac で叩いたキューを、',
      'バックアップの Mac の Live でも同時に再生します。',
      'メインが止まっても、すぐ切り替えられます。',
    ],
    download: (v: string) => `ダウンロード（${v}）`,
    readGuide: '使い方を見る',
    metaLong: 'macOS 13 以降・Apple シリコン / Intel・無料（MIT）',
    metaShort: 'macOS 13 以降・無料（MIT）・Apple の公証済み',
    notarized: 'Apple の公証済み。非公式のサードパーティ製ツールです。',
    screenshotAlt:
      'TwinKeys の画面。Backup Stage Mac に接続済み（遅延 2 ms）、近くの TwinKeys の一覧、キーとノートの設定が表示されています。',
    howTitle: 'しくみ',
    how: [
      ['メインの Mac', 'キーを押す → TwinKeys'],
      ['ネットワーク', '合言葉で暗号化'],
      ['バックアップの Mac', 'TwinKeys → Live'],
    ],
    howNote: 'メインの Mac の Live も、TwinKeys の MIDI ポートから同じキューを受け取ります。',
    featuresTitle: 'できること',
    features: [
      ['同時にキュー', 'キーを叩くと2台の Live で同じクリップが再生'],
      ['自動でつなぎ直す', '回線が切れても、戻ったら自動で再接続'],
      ['オールノートオフ', '両方の Mac の音を一度に止めるボタン'],
      ['合言葉で安全', '合言葉が同じ Mac だけがつながり、通信は暗号化'],
      ['届いたか分かる', 'キューがバックアップに届いたかを ✓ で表示'],
      ['日本語・英語', '画面もヘルプも両方の言語に対応'],
    ],
    stepsTitle: 'はじめかた',
    steps: ['両方の Mac に入れる', '同じ合言葉を設定', 'Live で TwinKeys をオン', '「接続」をクリック'],
    stepsMore: 'くわしい手順は「使い方」にあります。',
    guideTitle: '使い方',
    guideDocTitle: 'TwinKeys の使い方',
    releasesTitle: 'リリースノート',
    releasesDocTitle: 'リリースノート — TwinKeys',
    releasesLead: 'バージョンごとに、新しくなったことと直した不具合をまとめています。',
    latest: '最新',
    footerMade: '制作: Shogo Kajiyama / SEVENTHWELL',
    footerLicense: 'MIT License',
    footerTrademark:
      'TwinKeys は非公式のサードパーティ製ツールです。Ableton、Live は Ableton AG の商標です。',
    skip: '本文へ移動',
  },
} as const;
