// The "Connections" picture of the demo: Apple Watch - iPhone - a bracket to the two Macs stacked
// (main on top, backup below). Colours come from CSS classes so the site's light and dark themes apply.
import type { DemoText } from './remote-demo-text';

export type LinkState = 'ok' | 'dead' | 'switched';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function line(x1: number, y1: number, x2: number, y2: number, cls: string): string {
  return `<line class="ln ${cls}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;
}

function text(x: number, y: number, s: string, cls: string, anchor = 'start'): string {
  return `<text class="${cls}" x="${x}" y="${y}" text-anchor="${anchor}">${esc(s)}</text>`;
}

function xmark(x: number, y: number): string {
  return `<circle class="xm" cx="${x}" cy="${y}" r="9"/><text class="xm-t" x="${x}" y="${y + 4}" text-anchor="middle">✕</text>`;
}

type Kind = 'watch' | 'phone' | 'mac' | 'desk' | 'qlab';

function icon(kind: Kind, cx: number, cy: number): string {
  if (kind === 'qlab') return `<text class="ic-q" x="${cx}" y="${cy + 7}" text-anchor="middle">Q</text>`;
  if (kind === 'desk') {
    const faders = [0, 1, 2, 3].map((i) => `<rect x="${cx - 10 + i * 7}" y="${cy - 6}" width="2.5" height="12" rx="1" class="fillc"/><rect x="${cx - 12 + i * 7}" y="${cy - 2 + (i % 2) * 4}" width="6.5" height="3" rx="1" class="fillc"/>`).join('');
    return `<g class="ic"><rect x="${cx - 15}" y="${cy - 9}" width="30" height="18" rx="3"/>${faders}</g>`;
  }
  if (kind === 'watch')
    return `<g class="ic"><rect x="${cx - 7}" y="${cy - 15}" width="14" height="6" rx="2" class="fillc"/><rect x="${cx - 7}" y="${cy + 9}" width="14" height="6" rx="2" class="fillc"/><rect x="${cx - 10}" y="${cy - 10}" width="20" height="20" rx="6"/></g>`;
  if (kind === 'phone')
    return `<g class="ic"><rect x="${cx - 8}" y="${cy - 14}" width="16" height="28" rx="4"/><rect x="${cx - 3}" y="${cy + 9}" width="6" height="2" rx="1" class="fillc"/></g>`;
  return `<g class="ic"><rect x="${cx - 14}" y="${cy - 11}" width="28" height="18" rx="3"/><rect x="${cx - 4}" y="${cy + 8}" width="8" height="3" class="fillc"/><rect x="${cx - 8}" y="${cy + 11}" width="16" height="2" rx="1" class="fillc"/></g>`;
}

function node(kind: Kind, cx: number, cy: number, st: 'ok' | 'dead'): string {
  return `<g class="nd ${st}"><circle cx="${cx}" cy="${cy}" r="26"/>${icon(kind, cx, cy)}</g>`;
}

function badge(x: number, y: number, s: string): string {
  const w = Math.max(44, s.length * 9 + 18);
  return `<rect class="bd" x="${x}" y="${y - 13}" width="${w}" height="18" rx="9"/>${text(x + w / 2, y, s, 'bd-t', 'middle')}`;
}

/** QLab mode: what each Mac's QLab is doing ("▶ 12 Distant rain"), shown under its QLab. */
export interface QLabSubs {
  main: string;
  backup: string;
}

export function mapSvg(st: LinkState, t: DemoText, vertical: boolean, q?: QLabSubs): string {
  if (q) return vertical ? vMapQ(st, t, q) : hMapQ(st, t, q);
  return vertical ? vMap(st, t) : hMap(st, t);
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/** QLab: Watch - iPhone - bracket to Main (top) and Backup (bottom); each Mac into its own QLab (no console). */
function hMapQ(st: LinkState, t: DemoText, q: QLabSubs): string {
  const xw = 76, xp = 313, xj = 540, xm = 648, xq = 950, cy = 110, top = 48, bot = 172;
  const out: string[] = [];
  const okPhone = st === 'ok';
  const br = okPhone ? 'ok' : 'dead';
  const mainSt = st === 'ok' ? 'ok' : 'dead';
  out.push(line(xw + 28, cy, xp - 28, cy, 'ok'), text((xw + xp) / 2, cy - 10, t.linkWatch, 'lb', 'middle'));
  out.push(line(xp + 28, cy, xj, cy, br));
  out.push(text((xp + xj) / 2, cy - (okPhone ? 10 : 16), okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead', 'middle'));
  out.push(line(xj, top, xj, bot, br), line(xj, top, xm - 28, top, br), line(xj, bot, xm - 28, bot, br));
  if (okPhone) out.push(text(xj - 10, top + 4, t.direct, 'lb', 'end'), text(xj - 10, bot + 4, t.viaMain, 'lb', 'end'));
  else out.push(xmark((xp + xj) / 2, cy));
  // Each Mac drives the QLab on that Mac only.
  out.push(line(xm + 28, top, xq - 28, top, mainSt), line(xm + 28, bot, xq - 28, bot, 'ok'));
  out.push(text((xm + xq) / 2, top - 10, t.q.thisMacOnly, mainSt === 'ok' ? 'lb' : 'lb dead', 'middle'));
  out.push(text((xm + xq) / 2, bot - 10, t.q.thisMacOnly, 'lb', 'middle'));
  if (mainSt !== 'ok') out.push(xmark((xm + xq) / 2 + 90, top));
  if (st !== 'ok') {
    out.push(`<path class="ln ${st === 'dead' ? 'plan' : 'ok'}" fill="none" d="M${xp + 26} ${cy + 12} C ${xp + 90} ${cy + 60}, ${xm - 110} ${bot + 44}, ${xm - 30} ${bot + 12}"/>`);
    if (st === 'dead') out.push(text(xp - 60, bot + 86, t.plan, 'lb plan-t'));
  }
  out.push(node('watch', xw, cy, 'ok'), text(xw, cy + 46, t.watchTitle, 'nm', 'middle'), text(xw, cy + 62, t.watchLinked, 'sb ok', 'middle'));
  out.push(node('phone', xp, cy, st === 'dead' ? 'dead' : 'ok'), text(xp, cy + 46, 'iPhone', 'nm', 'middle'));
  out.push(text(xp, cy + 62, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok', 'middle'));
  out.push(node('mac', xm, top, mainSt), text(xm, top + 46, t.mainMac, 'nm', 'middle'));
  out.push(text(xm, top + 62, st === 'ok' ? t.q.qlabOk : t.noAnswer, st === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('mac', xm, bot, 'ok'), text(xm, bot + 46, t.backupMac, 'nm', 'middle'), text(xm, bot + 62, st === 'ok' ? t.q.qlabOk : t.backupPlaying, 'sb ok', 'middle'));
  if (st === 'ok') out.push(centeredBadge(xm, top - 33, t.mainBadge));
  if (st === 'switched') out.push(centeredBadge(xm, bot - 33, t.mainBadge));
  out.push(node('qlab', xq, top, mainSt), text(xq, top + 46, t.q.qlabMain, 'nm', 'middle'));
  out.push(text(xq, top + 62, mainSt === 'ok' ? clip(q.main, 30) : t.noAnswer, mainSt === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('qlab', xq, bot, 'ok'), text(xq, bot + 46, t.q.qlabBackup, 'nm', 'middle'), text(xq, bot + 62, clip(q.backup, 30), 'sb ok', 'middle'));
  return `<svg class="map-h" viewBox="0 0 1080 270" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

/** QLab on phones: Watch above the iPhone, the bracket opens down into Main (left) and Backup (right), each into its QLab below. */
function vMapQ(st: LinkState, t: DemoText, q: QLabSubs): string {
  const cx = 163, yw = 30, yp = 126, yj = 196, ym = 254, yq = 404, xl = 82, xr = 245;
  const okPhone = st === 'ok';
  const br = okPhone ? 'ok' : 'dead';
  const mainSt = st === 'ok' ? 'ok' : 'dead';
  const out: string[] = [];
  out.push(line(cx, yw + 28, cx, yp - 28, 'ok'), text(cx + 10, (yw + yp) / 2 + 4, t.linkWatch, 'lb'));
  out.push(line(cx, yp + 28, cx, yj, br), text(cx + 10, (yp + yj) / 2 + 16, okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead'));
  out.push(line(xl, yj, xr, yj, br), line(xl, yj, xl, ym - 28, br), line(xr, yj, xr, ym - 28, br));
  if (okPhone) out.push(text(xl - 6, yj + 20, t.direct, 'lb', 'end'), text(xr + 6, yj + 20, t.viaMain.replace('（LAN）', '').replace(' (LAN)', ''), 'lb'));
  else out.push(xmark(cx, (yp + yj) / 2 + 4));
  if (st !== 'ok') out.push(`<path class="ln ${st === 'dead' ? 'plan' : 'ok'}" fill="none" d="M${cx + 28} ${yp + 8} C ${xr + 60} ${yp + 20}, ${xr + 50} ${yj + 10}, ${xr + 20} ${ym - 26}"/>`);
  out.push(line(xl, ym + 72, xl, yq - 28, mainSt), line(xr, ym + 72, xr, yq - 28, 'ok'));
  out.push(text(cx, (ym + 72 + yq - 28) / 2 + 4, t.q.thisMacOnly, 'lb', 'middle'));
  if (mainSt !== 'ok') out.push(xmark(xl, (ym + 72 + yq - 28) / 2));
  out.push(node('watch', cx, yw, 'ok'), text(cx + 36, yw - 2, t.watchTitle, 'nm'), text(cx + 36, yw + 15, t.watchLinked, 'sb ok'));
  out.push(node('phone', cx, yp, st === 'dead' ? 'dead' : 'ok'), text(cx + 36, yp - 2, 'iPhone', 'nm'));
  out.push(text(cx + 36, yp + 15, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok'));
  const mainSub = st === 'ok' ? `${t.mainBadge} · ${t.q.qlabOk}` : t.noAnswer;
  const backSub = st === 'switched' ? `${t.mainBadge} · ${t.q.qlabOk}` : t.q.qlabOk;
  out.push(node('mac', xl, ym, mainSt), text(xl, ym + 46, t.mainMac, 'nm', 'middle'), text(xl, ym + 62, mainSub, mainSt === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('mac', xr, ym, 'ok'), text(xr, ym + 46, t.backupMac, 'nm', 'middle'), text(xr, ym + 62, backSub, 'sb ok', 'middle'));
  out.push(node('qlab', xl, yq, mainSt), text(xl, yq + 46, t.q.qlabMain, 'nm', 'middle'));
  out.push(text(xl, yq + 62, mainSt === 'ok' ? clip(q.main, 16) : t.noAnswer, mainSt === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('qlab', xr, yq, 'ok'), text(xr, yq + 46, t.q.qlabBackup, 'nm', 'middle'), text(xr, yq + 62, clip(q.backup, 16), 'sb ok', 'middle'));
  return `<svg class="map-v" viewBox="0 0 326 480" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

function centeredBadge(cx: number, y: number, s: string): string {
  const w = Math.max(44, s.length * 9 + 18);
  return badge(cx - w / 2, y, s);
}

function deskSub(st: LinkState, t: DemoText): string {
  return st === 'ok' ? t.deskMain : st === 'dead' ? t.deskPlan : t.deskBackup;
}

/** Watch - iPhone - bracket to Main (top) and Backup (bottom) - both into the console on the right. */
function hMap(st: LinkState, t: DemoText): string {
  const xw = 76, xp = 313, xj = 540, xm = 648, xd = 950, cy = 110, top = 48, bot = 172;
  const out: string[] = [];
  const okPhone = st === 'ok';
  const br = okPhone ? 'ok' : 'dead';
  out.push(line(xw + 28, cy, xp - 28, cy, 'ok'), text((xw + xp) / 2, cy - 10, t.linkWatch, 'lb', 'middle'));
  out.push(line(xp + 28, cy, xj, cy, br));
  out.push(text((xp + xj) / 2, cy - (okPhone ? 10 : 16), okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead', 'middle'));
  out.push(line(xj, top, xj, bot, br), line(xj, top, xm - 28, top, br), line(xj, bot, xm - 28, bot, br));
  if (okPhone) out.push(text(xj - 10, top + 4, t.direct, 'lb', 'end'), text(xj - 10, bot + 4, t.viaMain, 'lb', 'end'));
  else out.push(xmark((xp + xj) / 2, cy));
  // Both Macs into the console: sound and LAN.
  const mainDesk = st === 'ok' ? 'ok' : 'dead';
  out.push(line(xm + 28, top, xd - 26, cy - 10, mainDesk), line(xm + 28, bot, xd - 26, cy + 10, 'ok'));
  out.push(text((xm + xd) / 2 + 6, (top + cy) / 2 - 18, t.linkMainDesk, mainDesk === 'ok' ? 'lb' : 'lb dead', 'middle'));
  out.push(text((xm + xd) / 2 + 6, (bot + cy) / 2 + 30, t.linkBackupDesk, 'lb', 'middle'));
  if (mainDesk !== 'ok') out.push(xmark((xm + 28 + xd - 26) / 2 + 40, (top + cy - 10) / 2 + 5));
  if (st !== 'ok') {
    out.push(`<path class="ln ${st === 'dead' ? 'plan' : 'ok'}" fill="none" d="M${xp + 26} ${cy + 12} C ${xp + 90} ${cy + 60}, ${xm - 110} ${bot + 44}, ${xm - 30} ${bot + 12}"/>`);
    if (st === 'dead') out.push(text(xp - 60, bot + 86, t.plan, 'lb plan-t'));
  }
  out.push(node('watch', xw, cy, 'ok'), text(xw, cy + 46, t.watchTitle, 'nm', 'middle'), text(xw, cy + 62, t.watchLinked, 'sb ok', 'middle'));
  out.push(node('phone', xp, cy, st === 'dead' ? 'dead' : 'ok'), text(xp, cy + 46, 'iPhone', 'nm', 'middle'));
  out.push(text(xp, cy + 62, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok', 'middle'));
  out.push(node('mac', xm, top, st === 'ok' ? 'ok' : 'dead'), text(xm, top + 46, t.mainMac, 'nm', 'middle'));
  out.push(text(xm, top + 62, st === 'ok' ? t.liveOk : t.noAnswer, st === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('mac', xm, bot, 'ok'), text(xm, bot + 46, t.backupMac, 'nm', 'middle'), text(xm, bot + 62, st === 'ok' ? t.liveOk : t.backupPlaying, 'sb ok', 'middle'));
  if (st === 'ok') out.push(centeredBadge(xm, top - 33, t.mainBadge));
  if (st === 'switched') out.push(centeredBadge(xm, bot - 33, t.mainBadge));
  out.push(node('desk', xd, cy, 'ok'), text(xd, cy + 46, t.deskTitle, 'nm', 'middle'), text(xd, cy + 62, deskSub(st, t), 'sb ok', 'middle'));
  return `<svg class="map-h" viewBox="0 0 1080 270" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

/** Phones: Watch above the iPhone, the bracket opens down into Main (left) and Backup (right), both into the console below. */
function vMap(st: LinkState, t: DemoText): string {
  const cx = 163, yw = 30, yp = 126, yj = 196, ym = 254, yd = 404, xl = 82, xr = 245;
  const okPhone = st === 'ok';
  const br = okPhone ? 'ok' : 'dead';
  const out: string[] = [];
  out.push(line(cx, yw + 28, cx, yp - 28, 'ok'), text(cx + 10, (yw + yp) / 2 + 4, t.linkWatch, 'lb'));
  out.push(line(cx, yp + 28, cx, yj, br), text(cx + 10, (yp + yj) / 2 + 16, okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead'));
  out.push(line(xl, yj, xr, yj, br), line(xl, yj, xl, ym - 28, br), line(xr, yj, xr, ym - 28, br));
  if (okPhone) out.push(text(xl - 6, yj + 20, t.direct, 'lb', 'end'), text(xr + 6, yj + 20, t.viaMain.replace('（LAN）', '').replace(' (LAN)', ''), 'lb'));
  else out.push(xmark(cx, (yp + yj) / 2 + 4));
  if (st !== 'ok') out.push(`<path class="ln ${st === 'dead' ? 'plan' : 'ok'}" fill="none" d="M${cx + 28} ${yp + 8} C ${xr + 60} ${yp + 20}, ${xr + 50} ${yj + 10}, ${xr + 20} ${ym - 26}"/>`);
  const mainDesk = st === 'ok' ? 'ok' : 'dead';
  out.push(line(xl, ym + 70, cx - 14, yd - 26, mainDesk), line(xr, ym + 70, cx + 14, yd - 26, 'ok'));
  out.push(text(xl - 4, ym + 104, t.linkMainDesk.split(' ・ ')[0].split(' · ')[0], mainDesk === 'ok' ? 'lb' : 'lb dead', 'end'));
  out.push(text(xr + 4, ym + 104, t.linkBackupDesk.split(' ・ ')[0].split(' · ')[0], 'lb'));
  if (mainDesk !== 'ok') out.push(xmark((xl + cx - 14) / 2, (ym + 70 + yd - 26) / 2));
  out.push(node('watch', cx, yw, 'ok'), text(cx + 36, yw - 2, t.watchTitle, 'nm'), text(cx + 36, yw + 15, t.watchLinked, 'sb ok'));
  out.push(node('phone', cx, yp, st === 'dead' ? 'dead' : 'ok'), text(cx + 36, yp - 2, 'iPhone', 'nm'));
  out.push(text(cx + 36, yp + 15, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok'));
  const mainSub = st === 'ok' ? `${t.mainBadge} · ${t.liveOk}` : t.noAnswer;
  const backSub = st === 'switched' ? `${t.mainBadge} · ${t.backupPlaying}` : st === 'dead' ? t.backupPlaying : t.liveOk;
  out.push(node('mac', xl, ym, st === 'ok' ? 'ok' : 'dead'), text(xl, ym + 46, t.mainMac, 'nm', 'middle'), text(xl, ym + 62, mainSub, st === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('mac', xr, ym, 'ok'), text(xr, ym + 46, t.backupMac, 'nm', 'middle'), text(xr, ym + 62, backSub, 'sb ok', 'middle'));
  out.push(node('desk', cx, yd, 'ok'), text(cx, yd + 46, t.deskTitle, 'nm', 'middle'), text(cx, yd + 62, deskSub(st, t), 'sb ok', 'middle'));
  return `<svg class="map-v" viewBox="0 0 326 480" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

/** One sentence for screen readers, matching the picture. */
export function mapSummary(st: LinkState, t: DemoText, q?: QLabSubs): string {
  const phone = st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup;
  if (q)
    return `${t.mapTitle}: ${t.watchTitle} ${t.watchLinked}. iPhone ${phone}. ${t.mainMac} ${st === 'ok' ? `${t.q.qlabOk}, ${t.q.qlabMain} ${q.main}` : t.noAnswer}. ${t.backupMac} ${t.q.qlabOk}, ${t.q.qlabBackup} ${q.backup}. ${t.q.thisMacOnly}.`;
  return `${t.mapTitle}: ${t.watchTitle} ${t.watchLinked}. iPhone ${phone}. ${t.mainMac} ${st === 'ok' ? t.liveOk : t.noAnswer}. ${t.backupMac} ${st === 'ok' ? t.liveOk : t.backupPlaying}. ${t.deskTitle}: ${deskSub(st, t)}.`;
}
