// Live smoke test: two temporary accounts + tiny disposable documents only.
// No reset emails are sent, no existing account/document is read or changed.
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const config = JSON.parse(await readFile(new URL('../config/firebase-web.json', import.meta.url)));
assert.equal(config.projectId, 'taxi-logbook-d1104');
const authRoot = 'https://identitytoolkit.googleapis.com/v1/accounts:';
const database = `https://firestore.googleapis.com/v1/projects/${config.projectId}/databases/(default)/documents`;
const accounts = [];
const createdDocuments = [];
async function request(url, method, body, token) {
  const response = await fetch(url, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}
async function auth(action, body) {
  const result = await request(`${authRoot}${action}?key=${config.apiKey}`, 'POST', body);
  assert.equal(result.status, 200, `Auth ${action} failed (${result.status})`);
  return result.data;
}
const fieldData = (cents) => ({ fields: {
  id: { stringValue: 'ci-fare' }, at: { stringValue: '2026-10-05T12:00:00.000' },
  cents: { integerValue: String(cents) }, source: { stringValue: 'Taxi' },
  payment: { stringValue: 'cash' }, kilometers: { nullValue: null }, note: { stringValue: 'Disposable CI smoke test' },
} });
try {
  for (let i = 0; i < 2; i++) {
    const email = `taxi-logbook-ci-${randomUUID()}@example.com`;
    const password = `CI-${randomUUID()}!`;
    const account = await auth('signUp', { email, password, returnSecureToken: true });
    accounts.push(account);
    const login = await auth('signInWithPassword', { email, password, returnSecureToken: true });
    assert.equal(login.localId, account.localId);
  }
  const [owner, other] = accounts;
  const path = `${database}/users/${owner.localId}/trips/ci-fare`;
  let result = await request(path, 'PATCH', fieldData(2270), owner.idToken);
  assert.equal(result.status, 200, `Owner create denied (${result.status})`);
  createdDocuments.push({ path, token: owner.idToken });
  result = await request(path, 'GET', undefined, owner.idToken);
  assert.equal(result.status, 200);
  assert.equal(result.data.fields.cents.integerValue, '2270');
  for (const method of ['GET', 'PATCH', 'DELETE']) {
    result = await request(path, method, method === 'PATCH' ? fieldData(9999) : undefined, other.idToken);
    assert.equal(result.status, 403, `Foreign ${method} should be denied`);
  }
  result = await request(path, 'GET');
  assert.equal(result.status, 403, 'Signed-out reads must be denied');
  result = await request(path, 'PATCH', fieldData(3000), owner.idToken);
  assert.equal(result.status, 200);
  const sourcesPath = `${database}/users/${owner.localId}/settings/logbook`;
  result = await request(sourcesPath, 'PATCH', { fields: { sources: { arrayValue: { values: [{ stringValue: 'Zentrale' }] } } } }, owner.idToken);
  assert.equal(result.status, 200);
  createdDocuments.push({ path: sourcesPath, token: owner.idToken });
  result = await request(sourcesPath, 'GET', undefined, other.idToken);
  assert.equal(result.status, 403);
  result = await request(path, 'DELETE', undefined, owner.idToken);
  assert.equal(result.status, 200);
  result = await request(path, 'GET', undefined, owner.idToken);
  assert.equal(result.status, 404);
  console.log('Firebase live check passed: signup, login, own-trip CRUD, foreign/anonymous access denied.');
} finally {
  let cleanupFailed = false;
  for (const doc of createdDocuments) {
    const result = await request(doc.path, 'DELETE', undefined, doc.token).catch(() => null);
    if (!result || ![200, 404].includes(result.status)) cleanupFailed = true;
  }
  for (const account of accounts) {
    await auth('delete', { idToken: account.idToken }).catch(() => { cleanupFailed = true; });
  }
  if (cleanupFailed) throw new Error('Test cleanup failed; inspect temporary taxi-logbook-ci accounts.');
  if (accounts.length) console.log('Temporary test documents and accounts removed.');
}
