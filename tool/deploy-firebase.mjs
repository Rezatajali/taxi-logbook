// Deploys build/web to Firebase Hosting and firestore.rules via the REST APIs.
// Used by CI with a service account (GOOGLE_APPLICATION_CREDENTIALS). Unlike
// firebase-tools it needs no Service Usage permission, only Firebase access.
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import path from 'node:path';
import { GoogleAuth } from 'google-auth-library';

const project = 'taxi-logbook-d1104';
const site = project;
const root = new URL('..', import.meta.url).pathname;
const webDir = path.join(root, 'build/web');
const hostingApi = 'https://firebasehosting.googleapis.com/v1beta1';
const rulesApi = 'https://firebaserules.googleapis.com/v1';

const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
const client = await auth.getClient();

async function call(url, { method = 'GET', body, headers = {}, raw = false } = {}) {
  const response = await client.request({
    url, method, headers,
    data: body,
    responseType: raw ? 'text' : 'json',
    validateStatus: () => true,
  });
  if (response.status >= 300) {
    const detail = typeof response.data === 'string' ? response.data : JSON.stringify(response.data);
    throw new Error(`${method} ${url} -> ${response.status}: ${detail.slice(0, 500)}`);
  }
  return response.data;
}

async function listFiles(dir) {
  const result = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue; // firebase.json ignores dotfiles
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...await listFiles(full));
    else result.push(full);
  }
  return result;
}

// Same behaviour as firebase.json: SPA rewrite and security/cache headers.
function hostingConfig() {
  return readFile(path.join(root, 'firebase.json'), 'utf8').then((text) => {
    const hosting = JSON.parse(text).hosting;
    return {
      rewrites: hosting.rewrites.map((r) => ({ glob: r.source, path: r.destination })),
      headers: hosting.headers.map((h) => ({
        glob: h.source,
        headers: Object.fromEntries(h.headers.map((x) => [x.key, x.value])),
      })),
    };
  });
}

async function deployHosting() {
  const version = await call(`${hostingApi}/sites/${site}/versions`, {
    method: 'POST', body: { config: await hostingConfig() },
  });
  const files = {};
  const blobs = new Map();
  for (const file of await listFiles(webDir)) {
    const gz = gzipSync(await readFile(file), { level: 9 });
    const hash = createHash('sha256').update(gz).digest('hex');
    files['/' + path.relative(webDir, file).split(path.sep).join('/')] = hash;
    blobs.set(hash, gz);
  }
  const populated = await call(`${hostingApi}/${version.name}:populateFiles`, {
    method: 'POST', body: { files },
  });
  const required = populated.uploadRequiredHashes ?? [];
  for (const hash of required) {
    await call(`${populated.uploadUrl}/${hash}`, {
      method: 'POST', body: blobs.get(hash), raw: true,
      headers: { 'Content-Type': 'application/octet-stream' },
    });
  }
  await call(`${hostingApi}/${version.name}?update_mask=status`, {
    method: 'PATCH', body: { status: 'FINALIZED' },
  });
  await call(`${hostingApi}/sites/${site}/releases?versionName=${encodeURIComponent(version.name)}`, {
    method: 'POST', body: { message: `CI ${process.env.GITHUB_SHA ?? ''}`.trim() },
  });
  console.log(`Hosting: ${Object.keys(files).length} Dateien (${required.length} hochgeladen) -> https://${site}.web.app`);
}

async function deployRules() {
  const content = await readFile(path.join(root, 'firestore.rules'), 'utf8');
  const ruleset = await call(`${rulesApi}/projects/${project}/rulesets`, {
    method: 'POST', body: { source: { files: [{ name: 'firestore.rules', content }] } },
  });
  const releaseName = `projects/${project}/releases/cloud.firestore`;
  await call(`${rulesApi}/${releaseName}`, {
    method: 'PATCH', body: { release: { name: releaseName, rulesetName: ruleset.name } },
  });
  console.log(`Firestore-Regeln veröffentlicht: ${ruleset.name}`);
}

await deployHosting();
await deployRules();
