import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DMG_URL, fetchLatestRelease } from './latestRelease.ts';

const respond = (status: number, body: unknown = {}) => async () =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

test('returns the tag of the latest release', async () => {
  assert.deepEqual(await fetchLatestRelease(respond(200, { tag_name: 'v0.1.0' }), undefined), {
    kind: 'release',
    tag: 'v0.1.0',
  });
});

test('reports no release when the API returns 404', async () => {
  assert.deepEqual(await fetchLatestRelease(respond(404, { message: 'Not Found' }), undefined), { kind: 'none' });
});

test('reports unknown when rate-limited', async () => {
  assert.deepEqual(await fetchLatestRelease(respond(403, { message: 'API rate limit exceeded' }), undefined), {
    kind: 'unknown',
  });
});

test('reports unknown on a server error', async () => {
  assert.deepEqual(await fetchLatestRelease(respond(502), undefined), { kind: 'unknown' });
});

test('reports unknown when the network fails', async () => {
  const failing = async () => {
    throw new TypeError('fetch failed');
  };
  assert.deepEqual(await fetchLatestRelease(failing, undefined), { kind: 'unknown' });
});

test('reports unknown when the body has no tag', async () => {
  assert.deepEqual(await fetchLatestRelease(respond(200, { name: 'v0.1.0' }), undefined), { kind: 'unknown' });
});

test('sends the token when one is given', async () => {
  let seen: string | undefined;
  const spy = async (_url: string, init?: RequestInit) => {
    seen = (init?.headers as Record<string, string>).Authorization;
    return new Response('{}', { status: 404 });
  };
  await fetchLatestRelease(spy, 'abc');
  assert.equal(seen, 'Bearer abc');
});

test('the download link is the fixed-name asset of the latest release', () => {
  assert.equal(DMG_URL, 'https://github.com/aydenjahola/Hush/releases/latest/download/Hush.dmg');
});
