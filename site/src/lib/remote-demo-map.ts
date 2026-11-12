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

function icon(kind: 'watch' | 'phone' | 'mac', cx: number, cy: number): string {
  if (kind === 'watch')
    return `<g class="ic"><rect x="${cx - 7}" y="${cy - 15}" width="14" height="6" rx="2" class="fillc"/><rect x="${cx - 7}" y="${cy + 9}" width="14" height="6" rx="2" class="fillc"/><rect x="${cx - 10}" y="${cy - 10}" width="20" height="20" rx="6"/></g>`;
  if (kind === 'phone')
    return `<g class="ic"><rect x="${cx - 8}" y="${cy - 14}" width="16" height="28" rx="4"/><rect x="${cx - 3}" y="${cy + 9}" width="6" height="2" rx="1" class="fillc"/></g>`;
  return `<g class="ic"><rect x="${cx - 14}" y="${cy - 11}" width="28" height="18" rx="3"/><rect x="${cx - 4}" y="${cy + 8}" width="8" height="3" class="fillc"/><rect x="${cx - 8}" y="${cy + 11}" width="16" height="2" rx="1" class="fillc"/></g>`;
}

function node(kind: 'watch' | 'phone' | 'mac', cx: number, cy: number, st: 'ok' | 'dead'): string {
  return `<g class="nd ${st}"><circle cx="${cx}" cy="${cy}" r="26"/>${icon(kind, cx, cy)}</g>`;
}

function badge(x: number, y: number, s: string): string {
  const w = Math.max(44, s.length * 9 + 18);
  return `<rect class="bd" x="${x}" y="${y - 13}" width="${w}" height="18" rx="9"/>${text(x + w / 2, y, s, 'bd-t', 'middle')}`;
}

export function mapSvg(st: LinkState, t: DemoText, vertical: boolean): string {
  return vertical ? vMap(st, t) : hMap(st, t);
}

function hMap(st: LinkState, t: DemoText): string {
  const xw = 86, xp = 367, xj = 626, xm = 734, cy = 100, top = 48, bot = 152;
  const out: string[] = [];
  const okPhone = st === 'ok';
  out.push(line(xw + 28, cy, xp - 28, cy, 'ok'), text((xw + xp) / 2, cy - 10, t.linkWatch, 'lb', 'middle'));
  out.push(line(xp + 28, cy, xj, cy, okPhone ? 'ok' : 'dead'));
  out.push(text((xp + xj) / 2, cy - (okPhone ? 10 : 16), okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead', 'middle'));
  out.push(line(xj, top, xj, bot, okPhone ? 'ok' : 'dead'), line(xj, top, xm - 28, top, okPhone ? 'ok' : 'dead'), line(xj, bot, xm - 28, bot, okPhone ? 'ok' : 'dead'));
  if (okPhone) out.push(text(xj - 10, top + 4, t.direct, 'lb', 'end'), text(xj - 10, bot + 4, t.viaMain, 'lb', 'end'));
  else out.push(xmark((xp + xj) / 2, cy));
  if (st !== 'ok') {
    const cls = st === 'dead' ? 'plan' : 'ok';
    out.push(`<path class="ln ${cls}" fill="none" d="M${xp + 26} ${cy + 12} C ${xp + 110} ${cy + 40}, ${xm - 120} ${bot + 40}, ${xm - 30} ${bot + 12}"/>`);
    if (st === 'dead') out.push(text((xp + xm) / 2, bot + 50, t.plan, 'lb plan-t', 'middle'));
  }
  out.push(node('watch', xw, cy, 'ok'), text(xw, cy + 46, t.watchTitle, 'nm', 'middle'), text(xw, cy + 62, t.watchLinked, 'sb ok', 'middle'));
  out.push(node('phone', xp, cy, st === 'dead' ? 'dead' : 'ok'), text(xp, cy + 46, 'iPhone', 'nm', 'middle'));
  out.push(text(xp, cy + 62, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok', 'middle'));
  out.push(node('mac', xm, top, st === 'ok' ? 'ok' : 'dead'), text(xm + 38, top - 2, t.mainMac, 'nm'));
  out.push(text(xm + 38, top + 16, st === 'ok' ? t.liveReceived : t.noAnswer, st === 'ok' ? 'sb ok' : 'sb dead'));
  out.push(node('mac', xm, bot, 'ok'), text(xm + 38, bot - 2, t.backupMac, 'nm'));
  out.push(text(xm + 38, bot + 16, st === 'dead' ? t.backupUnreached : t.liveReceived, 'sb ok'));
  if (st === 'ok') out.push(badge(xm + 38 + t.mainMac.length * 7.6 + 8, top - 2, t.mainBadge));
  if (st === 'switched') out.push(badge(xm + 38 + t.backupMac.length * 7.6 + 8, bot - 2, t.mainBadge));
  return `<svg class="map-h" viewBox="0 0 1080 230" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

function vMap(st: LinkState, t: DemoText): string {
  const cx = 163, yw = 30, yp = 126, yj = 196, ym = 254, xl = 82, xr = 245;
  const okPhone = st === 'ok';
  const out: string[] = [];
  out.push(line(cx, yw + 28, cx, yp - 28, 'ok'), text(cx + 10, (yw + yp) / 2 + 4, t.linkWatch, 'lb'));
  out.push(line(cx, yp + 28, cx, yj, okPhone ? 'ok' : 'dead'), text(cx + 10, (yp + yj) / 2 + 16, okPhone ? t.linkPhone : t.noAnswer, okPhone ? 'lb' : 'lb dead'));
  out.push(line(xl, yj, xr, yj, okPhone ? 'ok' : 'dead'), line(xl, yj, xl, ym - 28, okPhone ? 'ok' : 'dead'), line(xr, yj, xr, ym - 28, okPhone ? 'ok' : 'dead'));
  if (okPhone) out.push(text(xl - 6, yj + 20, t.direct, 'lb', 'end'), text(xr + 6, yj + 20, t.viaMain.replace('（LAN）', '').replace(' (LAN)', ''), 'lb'));
  else out.push(xmark(cx, (yp + yj) / 2 + 4));
  if (st !== 'ok') out.push(`<path class="ln ${st === 'dead' ? 'plan' : 'ok'}" fill="none" d="M${cx + 28} ${yp + 8} C ${xr + 60} ${yp + 20}, ${xr + 50} ${yj + 10}, ${xr + 20} ${ym - 26}"/>`);
  out.push(node('watch', cx, yw, 'ok'), text(cx + 36, yw - 2, t.watchTitle, 'nm'), text(cx + 36, yw + 15, t.watchLinked, 'sb ok'));
  out.push(node('phone', cx, yp, st === 'dead' ? 'dead' : 'ok'), text(cx + 36, yp - 2, 'iPhone', 'nm'));
  out.push(text(cx + 36, yp + 15, st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup, st === 'dead' ? 'sb dead' : 'sb ok'));
  const mainSub = st === 'ok' ? `${t.mainBadge} · ${t.liveOk}` : t.noAnswer;
  const backSub = st === 'switched' ? `${t.mainBadge} · ${t.liveOk}` : t.liveOk;
  out.push(node('mac', xl, ym, st === 'ok' ? 'ok' : 'dead'), text(xl, ym + 46, t.mainMac, 'nm', 'middle'), text(xl, ym + 62, mainSub, st === 'ok' ? 'sb ok' : 'sb dead', 'middle'));
  out.push(node('mac', xr, ym, 'ok'), text(xr, ym + 46, t.backupMac, 'nm', 'middle'), text(xr, ym + 62, backSub, 'sb ok', 'middle'));
  return `<svg class="map-v" viewBox="0 0 326 330" role="img" aria-label="${esc(t.mapTitle)}">${out.join('')}</svg>`;
}

/** One sentence for screen readers, matching the picture. */
export function mapSummary(st: LinkState, t: DemoText): string {
  const phone = st === 'ok' ? t.phoneToMain : st === 'dead' ? t.phoneLost : t.phoneToBackup;
  return `${t.mapTitle}: ${t.watchTitle} ${t.watchLinked}. iPhone ${phone}. ${t.mainMac} ${st === 'ok' ? t.liveOk : t.noAnswer}. ${t.backupMac} ${t.liveOk}.`;
}
