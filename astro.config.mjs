// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const SITE = 'https://seo.project-n.site';

export default defineConfig({
  site: SITE,
  trailingSlash: 'never',
  integrations: [sitemap()],
  build: {
    inlineStylesheets: 'always',
  },
  compressHTML: true,
  prefetch: false,
});
