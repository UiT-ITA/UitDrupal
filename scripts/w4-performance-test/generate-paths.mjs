/**
 * Generate a list of internal paths by crawling https://www4.uib.no/.
 *
 * Usage:
 *   node ./scripts/w4-performance-test/generate-paths.mjs
 *
 * Tunables:
 *   MAX_PATHS=50                 How many unique paths to collect
 *   MAX_PAGES=200                Max pages to fetch during crawl
 *   START_URL=https://www4.uib.no/  Crawl starting point
 *   OUT_FILE=./scripts/w4-performance-test/paths.json
 */
import fs from 'node:fs/promises';

const START_URL = process.env.START_URL ?? 'https://www4.uib.no/';
const MAX_PATHS = Number.parseInt(process.env.MAX_PATHS ?? '50', 10);
const MAX_PAGES = Number.parseInt(process.env.MAX_PAGES ?? '200', 10);
const OUT_FILE = process.env.OUT_FILE ?? './scripts/w4-performance-test/paths.json';

const ASSET_EXT_RE = /\.(?:png|jpe?g|gif|webp|svg|ico|pdf|zip|gz|tgz|rar|7z|mp4|webm|mp3|wav|woff2?|ttf|otf|eot|css|js|map)$/i;
const SKIP_SCHEMES_RE = /^(?:mailto:|tel:|javascript:|data:)/i;

function normalizePathname(pathname) {
  if (!pathname) return null;
  if (!pathname.startsWith('/')) return null;
  if (pathname.length > 1 && pathname.endsWith('/')) pathname = pathname.slice(0, -1);
  if (pathname === '/en') return '/en'; // keep if present
  return pathname;
}

function shouldKeepPath(pathname) {
  if (!pathname) return false;
  if (pathname === '/') return true;
  if (ASSET_EXT_RE.test(pathname)) return false;
  if (pathname.startsWith('/sites/')) return false;
  if (pathname.startsWith('/system/')) return false;
  return true;
}

function extractHrefs(html) {
  // Lightweight <a href="..."> extraction without dependencies.
  const hrefs = [];
  const re = /<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^>\s]+))[^>]*>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = (m[1] ?? m[2] ?? m[3] ?? '').trim();
    if (href) hrefs.push(href);
  }
  return hrefs;
}

async function fetchHtml(url) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: {
      'User-Agent': 'w4-performance-test-path-crawler/1.0',
      Accept: 'text/html,application/xhtml+xml',
    },
  });

  const contentType = res.headers.get('content-type') ?? '';
  if (!contentType.includes('text/html')) {
    return { ok: res.ok, status: res.status, html: '' };
  }
  const html = await res.text();
  return { ok: res.ok, status: res.status, html };
}

async function main() {
  const start = new URL(START_URL);
  const baseOrigin = start.origin;

  const visited = new Set();
  const queue = [start.href];

  const collectedPaths = new Set();
  collectedPaths.add('/'); // keep frontpage

  while (queue.length > 0 && visited.size < MAX_PAGES && collectedPaths.size < MAX_PATHS) {
    const nextUrl = queue.shift();
    if (!nextUrl) break;
    if (visited.has(nextUrl)) continue;
    visited.add(nextUrl);

    let html = '';
    try {
      const fetched = await fetchHtml(nextUrl);
      html = fetched.html;
    } catch {
      continue;
    }

    if (!html) continue;
    for (const href of extractHrefs(html)) {
      if (SKIP_SCHEMES_RE.test(href)) continue;
      let u;
      try {
        u = new URL(href, nextUrl);
      } catch {
        continue;
      }
      if (u.origin !== baseOrigin) continue;

      // Strip query/hash to keep stable endpoints.
      u.hash = '';
      u.search = '';

      const pathname = normalizePathname(u.pathname);
      if (!shouldKeepPath(pathname)) continue;

      if (!collectedPaths.has(pathname) && collectedPaths.size < MAX_PATHS) {
        collectedPaths.add(pathname);
      }

      const canonical = u.href;
      if (!visited.has(canonical) && queue.length < MAX_PAGES * 2) {
        queue.push(canonical);
      }
    }
  }

  const paths = Array.from(collectedPaths);
  paths.sort((a, b) => a.localeCompare(b));

  const output = {
    generatedAt: new Date().toISOString(),
    startUrl: START_URL,
    maxPages: MAX_PAGES,
    maxPaths: MAX_PATHS,
    count: paths.length,
    paths,
  };

  await fs.mkdir(new URL('.', new URL(`file://${process.cwd()}/`)).pathname, { recursive: true }).catch(() => {});
  await fs.writeFile(OUT_FILE, JSON.stringify(output, null, 2) + '\n', 'utf8');

  if (paths.length < MAX_PATHS) {
    console.error(`Only collected ${paths.length}/${MAX_PATHS} paths. Consider raising MAX_PAGES or verifying START_URL.`);
    process.exitCode = 2;
  } else {
    console.log(`Wrote ${paths.length} paths to ${OUT_FILE}`);
  }
}

await main();
