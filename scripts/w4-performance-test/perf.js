import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';

const DEFAULT_DOMAINS = [
  'www4.uib.no',
  'w4.test.uib.no',
  'w4.bgo1.prod.rail.uib.no',
  'w4-novarnish.bgo1.test.rail.uib.no',
  'w4.bgo1.test.rail.uib.no',
];

const CACHE_MODES = [
  { name: 'cached', headers: {} },
  {
    name: 'no-cache',
    headers: {
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      Pragma: 'no-cache',
      Expires: '0',
    },
  },
];

function parseDomains() {
  const raw = (__ENV.DOMAINS ?? '').trim();
  if (!raw) return DEFAULT_DOMAINS;
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function readPaths() {
  const pathsFile = __ENV.PATHS_FILE ?? './scripts/w4-performance-test/paths.json';
  try {
    const raw = open(pathsFile);
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed;
    if (Array.isArray(parsed?.paths)) return parsed.paths;
  } catch (_) {
    // fall through
  }

  // Minimal fallback; generator should normally be used.
  return ['/'];
}

function buildThresholds(domains, pathsCount) {
  // We add lenient thresholds to force k6 to emit per-tag sub-metrics in the summary,
  // so we can format a per-domain/per-cacheMode report in handleSummary().
  const thresholds = {
    // Global sanity bounds (won't fail in normal conditions).
    http_req_failed: ['rate<1'],
    http_req_duration: ['p(99)<600000'],
  };

  for (const domain of domains) {
    for (const mode of CACHE_MODES) {
      const tag = `{domain:${domain},cacheMode:${mode.name}}`;
      thresholds[`http_req_duration${tag}`] = ['p(99)<600000'];
      thresholds[`http_req_failed${tag}`] = ['rate<1'];
      thresholds[`http_reqs${tag}`] = [`count>=${Math.min(pathsCount, 1)}`];
    }
  }

  return thresholds;
}

const domains = parseDomains();
const allPaths = readPaths();
const maxPaths = Number.parseInt(__ENV.MAX_PATHS ?? '50', 10);
const paths = allPaths.slice(0, Math.max(1, Math.min(maxPaths, allPaths.length)));

const batchSize = Number.parseInt(__ENV.BATCH_SIZE ?? '10', 10);
const perBatchSleepMs = Number.parseInt(__ENV.SLEEP_BETWEEN_BATCH_MS ?? '0', 10);
const baseProto = (__ENV.PROTO ?? 'https').trim() || 'https';
const requestTimeout = (__ENV.TIMEOUT ?? '30s').trim() || '30s';

const rps = Number.parseInt(__ENV.RPS ?? '', 10);
const duration = (__ENV.DURATION ?? '').trim();
const durationS = Number.parseInt(__ENV.DURATION_S ?? '', 10);
const hasRateMode = Number.isFinite(rps) && rps > 0 && (duration || (Number.isFinite(durationS) && durationS > 0));
const effectiveDuration = duration || (Number.isFinite(durationS) && durationS > 0 ? `${durationS}s` : '');

function buildTargets() {
  const out = [];
  for (const domain of domains) {
    for (const mode of CACHE_MODES) {
      for (const p of paths) {
        out.push({
          domain,
          cacheMode: mode.name,
          headers: mode.headers,
          path: safePath(p),
        });
      }
    }
  }
  return out;
}

const targets = buildTargets();

function preAllocatedVUsForRate(rate) {
  // Each iteration is one request; give enough VUs for slow tail without "dropped_iterations".
  // (This is deliberately conservative but bounded.)
  const v = Number.parseInt(__ENV.PREALLOCATED_VUS ?? '', 10);
  if (Number.isFinite(v) && v > 0) return v;
  return Math.min(200, Math.max(10, Math.ceil(rate / 2)));
}

export const options = {
  thresholds: buildThresholds(domains, paths.length),
  discardResponseBodies: true,
  noConnectionReuse: false,
  userAgent: __ENV.USER_AGENT ?? 'w4-performance-test-k6/1.0',
  ...(hasRateMode
    ? {
        scenarios: {
          rate: {
            executor: 'constant-arrival-rate',
            rate: rps,
            timeUnit: '1s',
            duration: effectiveDuration,
            preAllocatedVUs: preAllocatedVUsForRate(rps),
            maxVUs: Number.parseInt(__ENV.MAX_VUS ?? '', 10) || Math.min(500, preAllocatedVUsForRate(rps) * 2),
          },
        },
      }
    : {
        vus: Number.parseInt(__ENV.VUS ?? '1', 10),
        iterations: Number.parseInt(__ENV.ITERATIONS ?? '1', 10),
      }),
};

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function safePath(p) {
  if (!p) return '/';
  if (!p.startsWith('/')) return `/${p}`;
  return p;
}

export default function () {
  if (hasRateMode) {
    // One iteration == one request. We round-robin all (domain, cacheMode, path) targets.
    const idx = exec.scenario.iterationInTest % targets.length;
    const t = targets[idx];
    const url = `${baseProto}://${t.domain}${t.path}`;
    const r = http.get(url, {
      timeout: requestTimeout,
      headers: t.headers,
      tags: { domain: t.domain, cacheMode: t.cacheMode },
    });
    check(
      r,
      {
        'status is 2xx/3xx': (x) => x && x.status >= 200 && x.status < 400,
      },
      { domain: t.domain, cacheMode: t.cacheMode }
    );
    return;
  }

  const pathChunks = chunk(paths, Math.max(1, batchSize));

  for (const domain of domains) {
    for (const mode of CACHE_MODES) {
      for (const pChunk of pathChunks) {
        const reqs = pChunk.map((p) => {
          const path = safePath(p);
          const url = `${baseProto}://${domain}${path}`;
          return {
            method: 'GET',
            url,
            params: {
              timeout: requestTimeout,
              headers: mode.headers,
              tags: {
                domain,
                cacheMode: mode.name,
              },
            },
          };
        });

        const resps = http.batch(reqs);
        for (const r of resps) {
          check(
            r,
            {
              'status is 2xx/3xx': (x) => x && x.status >= 200 && x.status < 400,
            },
            { domain, cacheMode: mode.name }
          );
        }

        if (perBatchSleepMs > 0) sleep(perBatchSleepMs / 1000);
      }
    }
  }
}

function parseTagSelector(selector) {
  // selector like: "{domain:www4.uib.no,cacheMode:cached}"
  const s = selector.trim();
  if (!s.startsWith('{') || !s.endsWith('}')) return {};
  const inner = s.slice(1, -1).trim();
  if (!inner) return {};
  const out = {};
  for (const part of inner.split(',')) {
    const idx = part.indexOf(':');
    if (idx === -1) continue;
    const k = part.slice(0, idx).trim();
    const v = part.slice(idx + 1).trim();
    if (k) out[k] = v;
  }
  return out;
}

function pickTrend(metric) {
  const v = metric?.values ?? {};
  return {
    avg: v.avg,
    p50: v['p(50)'],
    p95: v['p(95)'],
    p99: v['p(99)'],
    min: v.min,
    max: v.max,
  };
}

function fmtMs(n) {
  if (n === undefined || n === null || Number.isNaN(n)) return 'n/a';
  return `${n.toFixed(1)}ms`;
}

function fmtPct01(n) {
  if (n === undefined || n === null || Number.isNaN(n)) return 'n/a';
  return `${(n * 100).toFixed(2)}%`;
}

export function handleSummary(data) {
  const outDir = (__ENV.OUT_DIR ?? './scripts/w4-performance-test/out').trim() || './scripts/w4-performance-test/out';
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');

  const byKey = new Map(); // key = domain|cacheMode

  for (const [metricName, metric] of Object.entries(data.metrics ?? {})) {
    const m = metricName.match(/^http_req_duration(\{.*\})$/);
    if (!m) continue;
    const tags = parseTagSelector(m[1]);
    if (!tags.domain || !tags.cacheMode) continue;

    const key = `${tags.domain}|${tags.cacheMode}`;
    const existing = byKey.get(key) ?? {
      domain: tags.domain,
      cacheMode: tags.cacheMode,
      duration: null,
      failedRate: null,
      reqs: null,
    };
    existing.duration = pickTrend(metric);
    byKey.set(key, existing);
  }

  for (const [metricName, metric] of Object.entries(data.metrics ?? {})) {
    const m = metricName.match(/^http_req_failed(\{.*\})$/);
    if (!m) continue;
    const tags = parseTagSelector(m[1]);
    if (!tags.domain || !tags.cacheMode) continue;
    const key = `${tags.domain}|${tags.cacheMode}`;
    const existing = byKey.get(key) ?? { domain: tags.domain, cacheMode: tags.cacheMode };
    existing.failedRate = metric?.values?.rate;
    byKey.set(key, existing);
  }

  for (const [metricName, metric] of Object.entries(data.metrics ?? {})) {
    const m = metricName.match(/^http_reqs(\{.*\})$/);
    if (!m) continue;
    const tags = parseTagSelector(m[1]);
    if (!tags.domain || !tags.cacheMode) continue;
    const key = `${tags.domain}|${tags.cacheMode}`;
    const existing = byKey.get(key) ?? { domain: tags.domain, cacheMode: tags.cacheMode };
    existing.reqs = metric?.values?.count;
    byKey.set(key, existing);
  }

  const domainsSorted = [...new Set([...byKey.values()].map((x) => x.domain))].sort((a, b) => a.localeCompare(b));
  const lines = [];
  lines.push(`# W4 performance test summary`);
  lines.push('');
  lines.push(`- generatedAt: ${new Date().toISOString()}`);
  lines.push(`- proto: ${baseProto}`);
  lines.push(`- pathsTested: ${paths.length}`);
  lines.push(`- batchSize: ${Math.max(1, batchSize)}`);
  if (hasRateMode) {
    lines.push(`- mode: constant-arrival-rate`);
    lines.push(`- rps: ${rps}`);
    lines.push(`- duration: ${effectiveDuration}`);
  } else {
    lines.push(`- mode: blast`);
    lines.push(`- vus: ${options.vus}`);
    lines.push(`- iterations: ${options.iterations}`);
  }
  lines.push('');

  for (const d of domainsSorted) {
    lines.push(`## ${d}`);
    lines.push('');
    for (const mode of CACHE_MODES) {
      const key = `${d}|${mode.name}`;
      const row = byKey.get(key);
      lines.push(`- **${mode.name}**`);
      if (!row) {
        lines.push('  - no data (likely no requests were tagged for this combination)');
        continue;
      }
      lines.push(`  - reqs: ${row.reqs ?? 'n/a'}`);
      lines.push(`  - http_req_failed: ${fmtPct01(row.failedRate)}`);
      lines.push(
        `  - http_req_duration: avg ${fmtMs(row.duration?.avg)}, p50 ${fmtMs(row.duration?.p50)}, p95 ${fmtMs(
          row.duration?.p95
        )}, p99 ${fmtMs(row.duration?.p99)}, min ${fmtMs(row.duration?.min)}, max ${fmtMs(row.duration?.max)}`
      );
    }
    lines.push('');
  }

  const summary = {
    generatedAt: new Date().toISOString(),
    proto: baseProto,
    pathsTested: paths.length,
    batchSize: Math.max(1, batchSize),
    mode: hasRateMode ? 'constant-arrival-rate' : 'blast',
    rps: hasRateMode ? rps : null,
    duration: hasRateMode ? effectiveDuration : null,
    vus: hasRateMode ? null : options.vus,
    iterations: hasRateMode ? null : options.iterations,
    results: [...byKey.values()].sort((a, b) =>
      a.domain === b.domain ? a.cacheMode.localeCompare(b.cacheMode) : a.domain.localeCompare(b.domain)
    ),
    k6: {
      state: data.state,
      rootGroup: data.root_group,
      options: data.options,
    },
  };

  const md = lines.join('\n') + '\n';
  const json = JSON.stringify(summary, null, 2) + '\n';

  return {
    stdout: md,
    [`${outDir}/summary-${stamp}.md`]: md,
    [`${outDir}/summary-${stamp}.json`]: json,
  };
}
