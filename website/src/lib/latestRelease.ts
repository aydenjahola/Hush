/**
 * Build-time lookup of the latest GitHub release, used by the download button.
 * Never throws: any failure becomes { kind: 'unknown' } so the build still succeeds.
 */

export const REPO = 'aydenjahola/Hush';
export const DMG_URL = `https://github.com/${REPO}/releases/latest/download/Hush.dmg`;

export type LatestRelease =
  | { kind: 'release'; tag: string }
  | { kind: 'none' }
  | { kind: 'unknown' };

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

export async function fetchLatestRelease(
  fetchImpl: Fetch = fetch,
  token: string | undefined = process.env.GITHUB_TOKEN,
): Promise<LatestRelease> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'hush-website-build',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  try {
    const response = await fetchImpl(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers,
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 404) return { kind: 'none' };
    if (!response.ok) return { kind: 'unknown' };
    const body: unknown = await response.json();
    const tag = (body as { tag_name?: unknown } | null)?.tag_name;
    return typeof tag === 'string' && tag.length > 0 ? { kind: 'release', tag } : { kind: 'unknown' };
  } catch {
    return { kind: 'unknown' };
  }
}

let cached: Promise<LatestRelease> | undefined;

/** Fetches once per build, however many pages ask. */
export function getLatestRelease(): Promise<LatestRelease> {
  cached ??= fetchLatestRelease();
  return cached;
}
