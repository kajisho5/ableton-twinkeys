import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

// Markdown lives outside site/ so the app, GitHub releases and this site share one source.
const releaseSchema = z.object({
  version: z.coerce.string(),
  date: z.union([z.date(), z.string()]).transform((d) =>
    d instanceof Date ? d.toISOString().slice(0, 10) : d,
  ),
});

const versionId = ({ entry }: { entry: string }) => entry.replace(/\.md$/, '');

export const collections = {
  help: defineCollection({
    loader: glob({ pattern: '*.md', base: '../docs/help' }),
  }),
  releasesEn: defineCollection({
    loader: glob({ pattern: '*.md', base: '../release-notes/en', generateId: versionId }),
    schema: releaseSchema,
  }),
  releasesJa: defineCollection({
    loader: glob({ pattern: '*.md', base: '../release-notes/ja', generateId: versionId }),
    schema: releaseSchema,
  }),
};
