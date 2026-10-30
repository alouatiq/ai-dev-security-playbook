// Tests the scan engine embedded in index.html: `node --test tests/`
// Fake credentials are split so secret scanners do not flag this file.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const block = (id) => new RegExp(`<script id="${id}">([\\s\\S]*?)</script>`).exec(html)[1];
const sandbox = { TextDecoder, setTimeout, console };
sandbox.globalThis = sandbox;
vm.runInNewContext(`${block('engine')}\n${block('demo')}\nglobalThis.Demo = Demo;`, sandbox);
const { Engine, Demo } = sandbox;

const AWS = 'AKIA' + 'QWERTYUIOPASDFGH';
const project = (files, git = {}) => ({
  files: Object.entries(files).map(([path, t]) => ({ path, size: t.length, read: async () => t })),
  gitFile: async (n) => git[n] ?? null,
});
const scan = (files, git, opts = {}) => Engine.quickScan({ ...project(files, git), ...opts }, { osv: !!opts.fetchFn });
const ids = (r) => r.findings.map((f) => f.id);

test('secrets are found and the value is never kept', async () => {
  const r = await scan({ 'app.py': `KEY = "${AWS}"\n` });
  assert.ok(ids(r).includes('G-07'));
  assert.ok(!JSON.stringify(r).includes(AWS));
  const md = Engine.toMarkdown('p', Engine.merge(r, [], null), r, null, 'now');
  assert.ok(!md.includes(AWS));
});

test('placeholders and example files are not reported as secrets', async () => {
  const r = await scan({ 'a.py': 'password = "changeme12345"\n', 'docs/setup.md': `KEY=${AWS}\n`, '.env.example': 'API_' + 'KEY="your-key-goes-here"\n' });
  assert.ok(!ids(r).includes('G-07'));
});

test('injection, XSS and CORS rules fire on real patterns', async () => {
  const r = await scan({
    'a.py': 'cur.execute(f"SELECT * FROM t WHERE id={i}")\n',
    'b.ts': 'db.query(`SELECT * FROM t WHERE id=${i}`);\n',
    'c.tsx': 'x.innerHTML = y;\n',
    'd.py': 'app.add_middleware(C, allow_origins=["*"])\n',
  });
  assert.equal(ids(r).filter((i) => i === 'G-01').length, 2);
  for (const id of ['G-02', 'F-03']) assert.ok(ids(r).includes(id), id);
});

test('safe code stays clean, and comments are ignored', async () => {
  const r = await scan({ 'a.py': '# cur.execute(f"SELECT {x}")\ncur.execute("SELECT * FROM t WHERE id=%s", (i,))\n', 'b.tsx': 'x.textContent = y;\n' });
  for (const id of ['G-01', 'G-02']) assert.ok(!ids(r).includes(id), id);
});

test('test code skips code rules but never secret rules; devsec-ignore cannot hide a secret', async () => {
  const sql = 'cur.execute(f"SELECT {x}")\n';
  const r = await scan({ 'tests/a.py': `${sql}KEY = "${AWS}"\n`, 'b.py': `cur.execute(f"SELECT {x}")  # devsec-ignore\nKEY = "${AWS}"  # devsec-ignore\n` });
  assert.ok(!ids(r).includes('G-01'));
  assert.equal(ids(r).filter((i) => i === 'G-07').length, 2);
});

test('routes without any auth fail; with auth they pass', async () => {
  const route = '@app.get("/x")\ndef x(): pass\n';
  assert.ok(ids(await scan({ 'a.py': route })).includes('F-01'));
  assert.ok(!ids(await scan({ 'a.py': `${route}u = Depends(user)\n` })).includes('F-01'));
});

test('workflow pins: branch fails, tag warns, SHA passes', async () => {
  const yml = 'steps:\n  - uses: a/b@master\n  - uses: c/d@v4\n  - uses: e/f@' + 'a'.repeat(40) + '\n  - uses: ./local\n';
  const hits = (await scan({ '.github/workflows/ci.yml': yml })).findings.filter((f) => f.id === 'C-01');
  assert.deepEqual([...hits.map((f) => f.status)], ['FAIL', 'WARN']);
});

test('Dockerfile: root user and floating tags are reported, multi-stage names are not', async () => {
  const r = await scan({ Dockerfile: 'FROM node:22 AS base\nFROM base\nUSER app\n', 'x/Dockerfile': 'FROM python:latest\n' });
  assert.deepEqual([...r.findings.filter((f) => /F-09|C-02/.test(f.id)).map((f) => `${f.id}:${f.file}`)].sort(), ['C-02:x/Dockerfile', 'F-09:x/Dockerfile']);
});

test('git index parsing finds tracked key files', async () => {
  // Minimal v2 index with one entry.
  const name = new TextEncoder().encode('deploy/prod.pem');
  const len = (62 + name.length + 8) & ~7;
  const bytes = new Uint8Array(12 + len);
  const v = new DataView(bytes.buffer);
  v.setUint32(0, 0x44495243); v.setUint32(4, 2); v.setUint32(8, 1);
  v.setUint16(12 + 60, name.length);
  bytes.set(name, 12 + 62);
  assert.deepEqual([...Engine.parseGitIndex(bytes)], ['deploy/prod.pem']);
  const r = await scan({}, { HEAD: new Uint8Array(1), index: bytes });
  assert.ok(ids(r).includes('G-03'));
});

test('lockfile parsers', () => {
  const pl = JSON.stringify({ packages: { '': {}, 'node_modules/a': { version: '1.0.0', resolved: 'https://registry.npmjs.org/a/-/a.tgz' }, 'node_modules/b/node_modules/@s/c': { version: '2.0.0' }, 'node_modules/priv': { version: '1.0.0', resolved: 'https://npm.corp.example/priv.tgz' } } });
  assert.deepEqual([...Engine.parseLock('package-lock.json', pl).map((d) => d.name)], ['a', '@s/c']);
  assert.equal(Engine.parseLock('requirements.txt', 'a==1\nb[x]==2 ; python_version>"3"\nc>=3\n').length, 2);
  assert.equal(Engine.parseLock('poetry.lock', '[[package]]\nname = "a"\nversion = "1"\n').length, 1);
  assert.equal(Engine.parseLock('go.sum', 'x.io/a v1.2.3 h1:q=\nx.io/a v1.2.3/go.mod h1:r=\n')[0].version, '1.2.3');
  assert.equal(Engine.parseLock('yarn.lock', '"@s/a@^1.0.0":\n  version "1.2.0"\n')[0].name, '@s/a');
  assert.equal(Engine.parseLock('Gemfile.lock', 'GEM\n  specs:\n    rack (2.0.1)\n      x (>= 1)\n')[0].name, 'rack');
  assert.equal(Engine.parseLock('package-lock.json', '{bad').length, 0);
});

test('OSV lookups: only name, version, ecosystem are sent; failure is not a pass', async () => {
  const sent = [];
  const fetchFn = async (url, init) => {
    if (init) sent.push(init.body);
    if (init) return { ok: true, json: async () => ({ results: [{ vulns: [{ id: 'GHSA-1' }] }] }) };
    return { ok: true, json: async () => ({ summary: 'bad', database_specific: { severity: 'MODERATE' } }) };
  };
  const r = await scan({ 'requirements.txt': 'a==1\n' }, {}, { fetchFn });
  const f = r.findings.find((x) => x.id === 'G-05');
  assert.equal(f.severity, 'Medium');
  assert.deepEqual(JSON.parse(sent[0]), { queries: [{ package: { name: 'a', ecosystem: 'PyPI' }, version: '1' }] });

  const failed = await scan({ 'requirements.txt': 'a==1\n' }, {}, { fetchFn: async () => { throw new Error('offline'); } });
  assert.equal(failed.coverage.osv, 'failed');
  assert.ok(!failed.ran.includes('G-05'));
});

test('a clean quick scan alone never gives a low-risk verdict', async () => {
  const r = await scan({ 'SECURITY.md': 'x\n' });
  assert.equal(Engine.merge(r, [], null).verdict, 'INCOMPLETE');
  const status = { phase: 'done', tools: ['gitleaks', 'osv-scanner', 'trivy'].map((tool) => ({ tool, state: 'ok' })) };
  assert.equal(Engine.merge(r, [], status).verdict, 'LOW');
  status.tools[1].state = 'failed';
  assert.equal(Engine.merge(r, [], status).verdict, 'INCOMPLETE');
});

test('deep results normalize across all five tools, with duplicates merged', () => {
  const raw = JSON.parse(JSON.stringify(Demo.deep));
  raw.trivy.Results.push({ Target: 'requirements.txt', Vulnerabilities: [{ VulnerabilityID: 'CVE-2024-24762', PkgName: 'fastapi', InstalledVersion: '0.95.0', Severity: 'HIGH' }] });
  const f = Engine.normalizeDeep(raw);
  for (const s of ['gitleaks', 'osv-scanner', 'trivy', 'zizmor', 'opengrep']) assert.ok(f.some((x) => x.source === s), s);
  assert.equal(f.find((x) => x.source === 'opengrep').file, 'app/main.py');
  assert.equal(f.find((x) => x.source === 'gitleaks').id, 'G-04');
  const merged = Engine.merge(null, f, raw.status);
  assert.equal(merged.findings.filter((x) => x.title.startsWith('fastapi')).length, 1);
});

test('deep command matches OS and page location', () => {
  assert.equal(Engine.deepCommand('file:///C:/Tools/My%20Book/index.html#x', 'windows'),
    'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\\Tools\\My Book\\scanner\\deep-scan.ps1"');
  assert.equal(Engine.deepCommand('file:///home/a/pb/index.html', 'linux'), 'bash "/home/a/pb/scanner/deep-scan.sh"');
  assert.equal(Engine.detectOs({ platform: 'Win32' }), 'windows');
  assert.equal(Engine.detectOs({ platform: 'MacIntel' }), 'macos');
  assert.equal(Engine.detectOs({ platform: 'Linux x86_64' }), 'linux');
});

test('the page has no innerHTML and allows only OSV as a network target', () => {
  const page = block('ui') + block('demo');
  assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML/.test(page));
  assert.match(html, /connect-src https:\/\/api\.osv\.dev;/);
});
