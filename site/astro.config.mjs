// @ts-check
import { defineConfig } from 'astro/config';

// https://docs.astro.build/en/reference/configuration-reference/
export default defineConfig({
  site: 'https://kajisho5.github.io',
  base: '/ableton-twinkeys',
  trailingSlash: 'always',
  build: { format: 'directory' },
});
