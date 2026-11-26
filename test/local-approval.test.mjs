import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomBytes, createHash } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import test from 'node:test';

test('OAuth pairing requires a local decision and revocation invalidates both tokens', { timeout: 15000 }, async t => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bridge-auth-'));
  const socket = net.createServer().listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  const base = `http://localhost:${port}`;
  const legacy = { expiresAt: Date.now() + 100000 };
  await writeFile(path.join(dir, 'state.json'), JSON.stringify({clients:{}, access:{legacy}, refresh:{legacy}}));
  const server = spawn(process.execPath, ['server.mjs'], {env: {...process.env, PUBLIC_URL: base, PORT: port,
    DOT_BRIDGE_DIR: dir, DOT_BRIDGE_STATUS_JSON: '1', DOT_BRIDGE_CHECK_ROUTE: '0'}});
  t.after(async () => {
    const closed = once(server, 'close');
    server.kill(); await closed; await rm(dir, {recursive: true, force: true});
  });
  const lines = createInterface({input:server.stdout})[Symbol.asyncIterator]();
  async function next(match) {
    for (;;) {
      const {value, done} = await lines.next();
      assert.ok(!done);
      if (!value.startsWith('DOTBRIDGE ')) continue;
      const event = JSON.parse(value.slice(10));
      if (match(event)) return event;
    }
  }
  const ready = await next(e => e.type === 'ready');
  const post = (route, fields) => fetch(base + route, {method:'POST', redirect:'manual', body:new URLSearchParams(fields)});
  const list = access => fetch(base + '/mcp', {method:'POST', headers:{authorization:`Bearer ${access}`,
    'content-type':'application/json', accept:'application/json, text/event-stream'}, body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/list'})});
  assert.equal((await list('legacy')).status, 401);
  const redirect = 'http://localhost/callback';
  const client = await (await fetch(base + '/register', {method:'POST', headers:{'content-type':'application/json'},
    body:JSON.stringify({redirect_uris:[redirect],token_endpoint_auth_method:'none'})})).json();
  const verifier = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  async function pair(decision) {
    const params = new URLSearchParams({client_id:client.client_id, redirect_uri:redirect, response_type:'code',
      code_challenge:challenge, code_challenge_method:'S256'});
    const page = await (await fetch(base + '/authorize?' + params)).text();
    const id = page.match(/name="id" value="([^"]+)"/)[1];
    const response = post('/approve', {id, code:ready.pairingCode});
    const event = await next(e => e.type === 'access' && e.requests.some(request => request.id === id));
    assert.equal(event.paired.length, 0);
    server.stdin.write(`${decision} ${id}\n`);
    return {id, result:await response};
  }
  assert.equal((await pair('deny')).result.status, 403);
  const {id,result} = await pair('approve');
  assert.equal(result.status, 302);
  const code = new URL(result.headers.get('location')).searchParams.get('code');
  const grant = await (await post('/token', {grant_type:'authorization_code',code,client_id:client.client_id,
    code_verifier:verifier,redirect_uri:redirect})).json();
  assert.equal((await list(grant.access_token)).status, 200);
  await next(e => e.type === 'access' && e.paired.some(client => client.id === id));
  server.stdin.write(`revoke ${id}\n`);
  await next(e => e.type === 'access' && !e.paired.length);
  assert.equal((await list(grant.access_token)).status, 401);
  assert.equal((await post('/token', {grant_type:'refresh_token', client_id:client.client_id,refresh_token:grant.refresh_token})).status, 400);
});
