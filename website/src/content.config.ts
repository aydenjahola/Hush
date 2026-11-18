import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
  // The repo-root CHANGELOG.md, written by release-please. It holds only a "# Changelog" heading until the first release.
  changelog: defineCollection({ loader: glob({ pattern: 'CHANGELOG.md', base: '..' }) }),
};
