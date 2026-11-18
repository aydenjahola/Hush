/** Prefixes a site path with Astro's base ("/Hush"), e.g. withBase('/using/mixer/'). */
export function withBase(path: string): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}
