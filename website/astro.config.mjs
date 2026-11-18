// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

export default defineConfig({
  site: 'https://aydenjahola.github.io',
  base: '/Hush',
  integrations: [
    starlight({
      title: 'Hush',
      description: "Per-app volume control for your Mac's menu bar.",
      favicon: '/favicon-32.png',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/aydenjahola/Hush' }],
      editLink: { baseUrl: 'https://github.com/aydenjahola/Hush/edit/main/website/' },
      head: [
        {
          tag: 'meta',
          attrs: { property: 'og:image', content: 'https://aydenjahola.github.io/Hush/logo-512.png' },
        },
      ],
      customCss: ['./src/styles/theme.css'],
      plugins: [starlightLinksValidator()],
      sidebar: [
        {
          label: 'Getting started',
          items: [
            { label: 'Install', slug: 'getting-started/install' },
            { label: 'First launch', slug: 'getting-started/first-launch' },
          ],
        },
        {
          label: 'Using Hush',
          items: [
            { label: 'The mixer', slug: 'using/mixer' },
            { label: 'Presets', slug: 'using/presets' },
            { label: 'Settings', slug: 'using/settings' },
            { label: 'Keyboard and accessibility', slug: 'using/keyboard-accessibility' },
          ],
        },
        {
          label: 'Help',
          items: [
            { label: 'Troubleshooting', slug: 'help/troubleshooting' },
            { label: 'Known limitations', slug: 'help/known-limitations' },
            { label: 'Privacy', slug: 'help/privacy' },
          ],
        },
        {
          label: 'Contributing',
          items: [
            { label: 'Build from source', slug: 'contributing/build-from-source' },
            { label: 'Architecture', slug: 'contributing/architecture' },
            { label: 'Testing', slug: 'contributing/testing' },
            { label: 'Performance budgets', slug: 'contributing/performance' },
            { label: 'Releasing', slug: 'contributing/releasing' },
          ],
        },
        { label: 'Changelog', slug: 'changelog' },
      ],
    }),
  ],
});
