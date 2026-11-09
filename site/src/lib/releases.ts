import { getCollection, type CollectionEntry } from 'astro:content';
import type { Lang } from './i18n';

type Release = CollectionEntry<'releasesEn'> | CollectionEntry<'releasesJa'>;

/** Semantic-version compare (major.minor.patch, pre-release sorts before release). */
export function compareVersions(a: string, b: string): number {
  const parse = (v: string) => {
    const [core, pre = ''] = v.replace(/^v/, '').split('-', 2);
    return { nums: core.split('.').map((n) => Number.parseInt(n, 10) || 0), pre };
  };
  const pa = parse(a);
  const pb = parse(b);
  for (let i = 0; i < Math.max(pa.nums.length, pb.nums.length); i++) {
    const d = (pa.nums[i] ?? 0) - (pb.nums[i] ?? 0);
    if (d !== 0) return d;
  }
  if (pa.pre === pb.pre) return 0;
  if (!pa.pre) return 1;
  if (!pb.pre) return -1;
  return pa.pre.localeCompare(pb.pre, 'en', { numeric: true });
}

/** Releases for a language, newest first. */
export async function getReleases(lang: Lang): Promise<Release[]> {
  const entries: Release[] = await getCollection(lang === 'ja' ? 'releasesJa' : 'releasesEn');
  return entries.sort((a, b) => compareVersions(b.data.version, a.data.version));
}

/** Version shown on the download button: the newest release note. */
export async function latestVersion(): Promise<string> {
  const [latest] = await getReleases('en');
  return latest?.data.version ?? '';
}
