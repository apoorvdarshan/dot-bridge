import { spawn } from 'node:child_process';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import express from 'express';
import * as z from 'zod/v4';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { mcpAuthRouter } from '@modelcontextprotocol/sdk/server/auth/router.js';
import { requireBearerAuth } from '@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js';
import { InvalidRequestError, InvalidGrantError, InvalidTokenError } from '@modelcontextprotocol/sdk/server/auth/errors.js';

const PORT = Number(process.env.PORT || 8787);
const DATA_DIR = process.env.DOT_BRIDGE_DIR || path.join(os.homedir(), '.dot-bridge');
const ROOTS = (process.env.DOT_BRIDGE_ROOTS || os.homedir()).split(':').map(r => path.resolve(r));
const MAX_OUTPUT = 60_000;
const ACCESS_TTL = 3600;
const REFRESH_TTL = 30 * 24 * 3600;

fs.mkdirSync(DATA_DIR, { recursive: true, mode: 0o700 });
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const LOG_FILE = path.join(DATA_DIR, 'activity.log');

const state = loadState();
function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return { clients: {}, access: {}, refresh: {} };
  }
}
function saveState() {
  const now = Date.now();
  for (const kind of ['access', 'refresh']) {
    for (const [k, v] of Object.entries(state[kind])) if (v.expiresAt < now) delete state[kind][k];
  }
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), { mode: 0o600 });
}
function log(event, detail = {}) {
  const line = JSON.stringify({ t: new Date().toISOString(), event, ...detail });
  fs.appendFileSync(LOG_FILE, line + '\n', { mode: 0o600 });
  console.log(`[${event}]`, JSON.stringify(detail).slice(0, 300));
}

async function startQuickTunnel() {
  return new Promise((resolve, reject) => {
    const proc = spawn('cloudflared', ['tunnel', '--no-autoupdate', '--url', `http://127.0.0.1:${PORT}`], {
      stdio: ['ignore', 'pipe', 'pipe']
    });
    const onData = buf => {
      const m = buf.toString().match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
      if (m) resolve(m[0]);
    };
    proc.stdout.on('data', onData);
    proc.stderr.on('data', onData);
    proc.on('exit', code => reject(new Error(`cloudflared exited with ${code}`)));
    process.on('exit', () => proc.kill());
    setTimeout(() => reject(new Error('Timed out waiting for the Cloudflare tunnel URL')), 30_000);
  });
}

const PUBLIC_URL = (process.env.PUBLIC_URL || (await startQuickTunnel())).replace(/\/$/, '');
const MCP_URL = new URL('/mcp', PUBLIC_URL);
const PAIRING_CODE = String(100000 + (randomBytes(4).readUInt32BE() % 900000));

const pending = new Map();
const codes = new Map();

const clientsStore = {
  async getClient(id) {
    return state.clients[id];
  },
  async registerClient(client) {
    state.clients[client.client_id] = client;
    saveState();
    log('client_registered', { client_id: client.client_id, name: client.client_name });
    return client;
  }
};

function issueTokens(clientId, scopes, resource) {
  const access = randomBytes(32).toString('hex');
  const refresh = randomBytes(32).toString('hex');
  const now = Date.now();
  state.access[access] = { clientId, scopes, resource, expiresAt: now + ACCESS_TTL * 1000 };
  state.refresh[refresh] = { clientId, scopes, resource, expiresAt: now + REFRESH_TTL * 1000 };
  saveState();
  return { access_token: access, token_type: 'bearer', expires_in: ACCESS_TTL, refresh_token: refresh, scope: scopes.join(' ') };
}

const provider = {
  clientsStore,
  async authorize(client, params, res) {
    if (!client.redirect_uris.includes(params.redirectUri)) throw new InvalidRequestError('Unregistered redirect_uri');
    const id = randomUUID();
    pending.set(id, { client, params, expiresAt: Date.now() + 10 * 60_000 });
    res.type('html').send(approvalPage(id, client.client_name || client.client_id));
  },
  async challengeForAuthorizationCode(_client, code) {
    const data = codes.get(code);
    if (!data) throw new InvalidGrantError('Invalid authorization code');
    return data.params.codeChallenge;
  },
  async exchangeAuthorizationCode(client, code) {
    const data = codes.get(code);
    if (!data || data.expiresAt < Date.now()) throw new InvalidGrantError('Invalid authorization code');
    if (data.client.client_id !== client.client_id) throw new InvalidGrantError('Code was issued to another client');
    codes.delete(code);
    log('authorized', { client_id: client.client_id });
    return issueTokens(client.client_id, data.params.scopes || [], data.params.resource?.href);
  },
  async exchangeRefreshToken(client, refreshToken) {
    const data = state.refresh[refreshToken];
    if (!data || data.expiresAt < Date.now() || data.clientId !== client.client_id) throw new InvalidGrantError('Invalid refresh token');
    delete state.refresh[refreshToken];
    return issueTokens(client.client_id, data.scopes, data.resource);
  },
  async verifyAccessToken(token) {
    const data = state.access[token];
    if (!data || data.expiresAt < Date.now()) throw new InvalidTokenError('Invalid or expired token');
    return {
      token,
      clientId: data.clientId,
      scopes: data.scopes,
      expiresAt: Math.floor(data.expiresAt / 1000),
      resource: data.resource ? new URL(data.resource) : undefined
    };
  },
  async revokeToken(_client, { token }) {
    delete state.access[token];
    delete state.refresh[token];
    saveState();
  }
};

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}
function approvalPage(id, clientName, error = '') {
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>dot-bridge</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;max-width:420px;margin:60px auto;padding:0 20px;color:#111}
h1{font-size:22px}input{font-size:24px;letter-spacing:6px;width:100%;padding:10px;box-sizing:border-box;margin:12px 0}
button{font-size:17px;padding:12px;width:100%;background:#111;color:#fff;border:0;border-radius:8px}.err{color:#c00}
.warn{background:#fff4e5;padding:12px;border-radius:8px;font-size:14px}</style></head><body>
<h1>Allow access to ${escapeHtml(os.hostname())}?</h1>
<p><b>${escapeHtml(clientName)}</b> wants to run commands and read and write files on this Mac.</p>
<p class="warn">Only approve if you just added dot-bridge in ChatGPT. Enter the pairing code shown in the dot-bridge terminal.</p>
${error ? `<p class="err">${escapeHtml(error)}</p>` : ''}
<form method="post" action="/approve"><input type="hidden" name="id" value="${escapeHtml(id)}">
<input name="code" inputmode="numeric" autocomplete="one-time-code" placeholder="000000" autofocus required>
<button type="submit">Allow access</button></form></body></html>`;
}

let failedAttempts = 0;
function codeMatches(input) {
  const a = Buffer.from(String(input).trim());
  const b = Buffer.from(PAIRING_CODE);
  return a.length === b.length && timingSafeEqual(a, b);
}

function resolveAllowed(p) {
  const abs = path.resolve(p.replace(/^~(?=$|\/)/, os.homedir()));
  let real;
  try {
    real = fs.realpathSync(abs);
  } catch {
    real = path.join(fs.realpathSync(path.dirname(abs)), path.basename(abs));
  }
  if (!ROOTS.some(r => real === r || real.startsWith(r + path.sep))) {
    throw new Error(`Path is outside the allowed folders (${ROOTS.join(', ')}): ${real}`);
  }
  return real;
}
function clip(s) {
  return s.length > MAX_OUTPUT ? s.slice(0, MAX_OUTPUT) + `\n…[truncated ${s.length - MAX_OUTPUT} chars]` : s;
}
const text = t => ({ content: [{ type: 'text', text: t }] });

function runProcess(cmd, args, { cwd, timeoutMs, input }) {
  return new Promise(resolve => {
    const child = spawn(cmd, args, { cwd, env: process.env });
    let out = '';
    const collect = d => {
      out += d.toString();
      if (out.length > MAX_OUTPUT * 2) out = out.slice(-MAX_OUTPUT * 2);
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    if (input) child.stdin.end(input);
    else child.stdin.end();
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal, out });
    });
  });
}

const jobs = new Map();

function buildServer() {
  const server = new McpServer({ name: 'dot-bridge', version: '0.1.0' });

  server.registerTool('computer_info', {
    title: 'Computer info',
    description: 'Describe this Mac: hostname, user, OS, and folders the bridge may access.',
    annotations: { readOnlyHint: true }
  }, async () => {
    log('tool', { name: 'computer_info' });
    return text(JSON.stringify({ hostname: os.hostname(), user: os.userInfo().username, os: `${os.type()} ${os.release()}`, arch: os.arch(), home: os.homedir(), allowedRoots: ROOTS }, null, 2));
  });

  server.registerTool('list_files', {
    title: 'List files',
    description: 'List entries in a directory on this Mac.',
    inputSchema: { path: z.string().describe('Absolute path or ~/…') },
    annotations: { readOnlyHint: true }
  }, async ({ path: p }) => {
    const dir = resolveAllowed(p);
    log('tool', { name: 'list_files', path: dir });
    const entries = fs.readdirSync(dir, { withFileTypes: true }).map(e => `${e.isDirectory() ? 'd' : '-'} ${e.name}`);
    return text(clip(entries.join('\n') || '(empty)'));
  });

  server.registerTool('read_file', {
    title: 'Read file',
    description: 'Read a UTF-8 text file on this Mac.',
    inputSchema: { path: z.string().describe('Absolute path or ~/…') },
    annotations: { readOnlyHint: true }
  }, async ({ path: p }) => {
    const file = resolveAllowed(p);
    log('tool', { name: 'read_file', path: file });
    return text(clip(fs.readFileSync(file, 'utf8')));
  });

  server.registerTool('write_file', {
    title: 'Write file',
    description: 'Create or overwrite a text file on this Mac.',
    inputSchema: { path: z.string(), content: z.string() },
    annotations: { readOnlyHint: false, destructiveHint: true }
  }, async ({ path: p, content }) => {
    const file = resolveAllowed(p);
    log('tool', { name: 'write_file', path: file, bytes: content.length });
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
    return text(`Wrote ${content.length} chars to ${file}`);
  });

  server.registerTool('run_command', {
    title: 'Run shell command',
    description: 'Run a zsh command on this Mac and return its combined output.',
    inputSchema: {
      command: z.string(),
      cwd: z.string().optional().describe('Working directory, defaults to home'),
      timeout_seconds: z.number().int().min(1).max(600).optional()
    },
    annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: true }
  }, async ({ command, cwd, timeout_seconds }) => {
    const dir = resolveAllowed(cwd || os.homedir());
    log('tool', { name: 'run_command', cwd: dir, command });
    const r = await runProcess('/bin/zsh', ['-lc', command], { cwd: dir, timeoutMs: (timeout_seconds || 120) * 1000 });
    return text(clip(`exit=${r.code ?? r.signal}\n${r.out}`));
  });

  server.registerTool('start_codex_task', {
    title: 'Start Codex task',
    description: 'Start a Codex CLI task (codex exec) in a local folder. Returns a job id; poll with codex_task_status.',
    inputSchema: { prompt: z.string(), cwd: z.string().describe('Project folder') },
    annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: true }
  }, async ({ prompt, cwd }) => {
    const dir = resolveAllowed(cwd);
    const id = randomUUID().slice(0, 8);
    log('tool', { name: 'start_codex_task', cwd: dir, job: id, prompt: prompt.slice(0, 200) });
    const job = { id, cwd: dir, prompt, status: 'running', startedAt: new Date().toISOString(), output: '' };
    jobs.set(id, job);
    runProcess('codex', ['exec', '--cd', dir, '--skip-git-repo-check', '-'], { cwd: dir, timeoutMs: 60 * 60_000, input: prompt }).then(r => {
      job.status = r.code === 0 ? 'completed' : 'failed';
      job.exit = r.code ?? r.signal;
      job.output = r.out;
      job.finishedAt = new Date().toISOString();
      log('codex_done', { job: id, status: job.status });
    });
    return text(`Started Codex job ${id} in ${dir}`);
  });

  server.registerTool('codex_task_status', {
    title: 'Codex task status',
    description: 'Get status and output of a Codex job, or list all jobs if no id is given.',
    inputSchema: { id: z.string().optional() },
    annotations: { readOnlyHint: true }
  }, async ({ id }) => {
    if (!id) return text(JSON.stringify([...jobs.values()].map(({ output, ...j }) => j), null, 2) || '[]');
    const job = jobs.get(id);
    if (!job) return text(`No job ${id}`);
    return text(clip(JSON.stringify({ ...job, output: undefined }, null, 2) + '\n\n' + job.output.slice(-MAX_OUTPUT)));
  });

  return server;
}

const app = express();
app.set('trust proxy', 1);
app.disable('x-powered-by');

app.use(mcpAuthRouter({
  provider,
  issuerUrl: new URL(PUBLIC_URL),
  resourceServerUrl: MCP_URL,
  scopesSupported: ['mcp'],
  resourceName: `dot-bridge (${os.hostname()})`
}));

app.post('/approve', express.urlencoded({ extended: false }), (req, res) => {
  const p = pending.get(req.body.id);
  if (!p || p.expiresAt < Date.now()) return res.status(400).type('html').send('<p>This request expired. Reconnect from ChatGPT.</p>');
  if (failedAttempts >= 5) return res.status(429).type('html').send('<p>Too many wrong codes. Restart dot-bridge.</p>');
  if (!codeMatches(req.body.code)) {
    failedAttempts++;
    log('approval_failed', { attempts: failedAttempts });
    return res.status(401).type('html').send(approvalPage(req.body.id, p.client.client_name || p.client.client_id, 'Wrong code.'));
  }
  pending.delete(req.body.id);
  const code = randomBytes(24).toString('hex');
  codes.set(code, { client: p.client, params: p.params, expiresAt: Date.now() + 5 * 60_000 });
  const target = new URL(p.params.redirectUri);
  target.searchParams.set('code', code);
  if (p.params.state !== undefined) target.searchParams.set('state', p.params.state);
  res.redirect(target.toString());
});

const auth = requireBearerAuth({
  verifier: provider,
  resourceMetadataUrl: new URL('/.well-known/oauth-protected-resource/mcp', PUBLIC_URL).href
});

app.post('/mcp', auth, express.json({ limit: '10mb' }), async (req, res) => {
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on('close', () => {
    transport.close();
    server.close();
  });
  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    log('mcp_error', { message: err.message });
    if (!res.headersSent) res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Internal error' }, id: null });
  }
});
app.all('/mcp', (_req, res) => res.status(405).set('Allow', 'POST').end());
app.get('/', (_req, res) => res.type('text').send('dot-bridge is running.'));

app.listen(PORT, '127.0.0.1', () => {
  console.log(`
dot-bridge is running on this Mac (${os.hostname()})

  MCP server URL:  ${MCP_URL.href}
  Pairing code:    ${PAIRING_CODE}
  Allowed folders: ${ROOTS.join(', ')}
  Activity log:    ${LOG_FILE}

Add it in ChatGPT on the web: Plugins → + → Add custom MCP server,
paste the URL above, choose OAuth, then enter the pairing code when asked.
`);
});
