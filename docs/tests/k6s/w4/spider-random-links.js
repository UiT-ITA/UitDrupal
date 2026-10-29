import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  noConnectionReuse: true,
  scenarios: {
    spider: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '10s',
      tags: { scenario: 'spider' },
    },
  },
  thresholds: {
    'http_req_duration{scenario:spider}': ['p(95)<2000'],
    'http_req_failed{scenario:spider}': ['rate<0.05'],
  },
};

// Change this for each environment.
// const baseUrl = 'https://www4.uib.no';
// const baseUrl = 'https://w4.uib.no';
const baseUrl = 'https://w4.bgo1.prod.rail.uib.no';
//const baseUrl = 'https://w4-novarnish.bgo1.prod.rail.uib.no';
//const baseUrl = 'https://w4.bgo1.test.rail.uib.no';
// const baseUrl = 'https://w4-novarnish.bgo1.test.rail.uib.no';
// const baseUrl = 'https://varnish.uib.ddev.site';
// const baseUrl = 'https://uib.ddev.site';

const seedPaths = [
  '/',
  '/om-uib',
  '/studier',
  '/studier/program',
  '/studier/emner',
  '/studier/nettstudier-og-videreutdanning',
  '/forskning/phd-utdanning',
  '/studier/hvilken-grad-vil-du-ta',
  '/studier/program/anvendt-og-utrekningsorientert-matematikk-master',
  '/studier/program/utovende-musikk-eller-komposisjon-master',
  '/forskning',
  '/forskning/finn-en-forsker',
  '/forskning/finn-en-forsker/eksperter-fra-uib-strafferett',
  '/forskning/forskergrupper',
  '/forskning/forskergrupper/appel-gruppen',
  '/forskning/forskningsprosjekter',
  '/forskning/forskningsprosjekter/ft-bergen',
  '/forskning/forskningssentre',
  '/forskning/forskningssentre/bergen-offshore-wind-centre-bow',
];

// k6 VUs are isolated runtimes; this state is per-VU.
let nextPath = '';

const CRAWL_DEPTH = 10; // Number of pages each VU crawls per iteration

function randomFrom(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function normalizeInternalPath(href, currentPath) {
  if (!href) return null;

  const trimmed = href.trim();
  if (
    trimmed === '' ||
    trimmed.startsWith('#') ||
    trimmed.startsWith('mailto:') ||
    trimmed.startsWith('tel:') ||
    trimmed.startsWith('javascript:')
  ) {
    return null;
  }

  try {
    const currentUrl = new URL(currentPath, baseUrl);
    const resolved = new URL(trimmed, currentUrl);
    const base = new URL(baseUrl);

    if (resolved.host !== base.host) {
      return null;
    }

    return `${resolved.pathname}${resolved.search}`;
  } catch (_) {
    return null;
  }
}

function extractInternalLinks(body, currentPath) {
  const unique = new Set();

  const hrefRegex = /<a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1/gi;
  let match;

  while ((match = hrefRegex.exec(body)) !== null) {
    const href = match[2];
    const normalized = normalizeInternalPath(href, currentPath);
    if (normalized) {
      unique.add(normalized);
    }
  }

  return Array.from(unique);
}

export default function () {
  let path = nextPath || randomFrom(seedPaths);

  // Crawl CRAWL_DEPTH pages deep
  for (let i = 0; i < CRAWL_DEPTH; i++) {
    const url = `${baseUrl}${path}`;

    const res = http.get(url);

    check(res, {
      'status is 200': (r) => r.status === 200,
    });

    const contentType = (res.headers['Content-Type'] || '').toLowerCase();
    if (res.status === 200 && contentType.includes('text/html')) {
      const links = extractInternalLinks(res.body, path);
      path = links.length > 0 ? randomFrom(links) : randomFrom(seedPaths);
    } else {
      path = randomFrom(seedPaths);
    }

    // Sleep between each page request
    sleep(0.5 + Math.random() * 0.5);
  }

  // Store the last path for next iteration
  nextPath = path;

  // Small sleep between crawl batches
  sleep(1);
}
