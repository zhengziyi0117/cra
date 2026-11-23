// Exercise the packaged DevKit, including OAuth and encrypted storage. Only the loopback callback uses a socket.
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import { EventEmitter, once } from 'node:events';
import { generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

async function mockProvider(helper) {
  const issuer = 'https://auth.openai.com';
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const localFetch = globalThis.fetch;
  let nonce;
  cp.spawn = (command, [address]) => {
    assert.equal(command, 'open');
    const url = new URL(address);
    assert.equal(url.origin, issuer);
    assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
    nonce = url.searchParams.get('nonce');
    const callback = new URL(url.searchParams.get('redirect_uri'));
    assert.equal(callback.hostname, '127.0.0.1');
    callback.search = new URLSearchParams({ code: 'test-code', state: url.searchParams.get('state'), client_id: 'test-client' });
    const child = new EventEmitter();
    localFetch(callback).then(() => child.emit('exit', 0), error => { console.error(error); child.emit('error', error); });
    return child;
  };
  globalThis.fetch = async (url, options = {}) => {
    switch (String(url)) {
    case issuer + '/.well-known/openid-configuration':
      return Response.json({ issuer, authorization_endpoint: issuer + '/authorize', token_endpoint: issuer + '/token',
        revocation_endpoint: issuer + '/revoke', jwks_uri: issuer + '/keys' });
    case issuer + '/keys':
      return Response.json({ keys: [{ ...publicKey.export({ format: 'jwk' }), kid: 'test', alg: 'RS256' }] });
    case issuer + '/token': {
      const now = Math.floor(Date.now() / 1000);
      const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
      const claims = { iss: issuer, aud: 'test-client', sub: 'test-user', iat: now, exp: now + 3600, nonce, email: 'test@example.invalid' };
      const body = encode({ alg: 'RS256', kid: 'test' }) + '.' + encode(claims);
      return Response.json({ token_type: 'bearer', access_token: 'synthetic-access', refresh_token: 'synthetic-refresh',
        id_token: body + '.' + sign('RSA-SHA256', Buffer.from(body), privateKey).toString('base64url'), expires_in: 3600,
        scope: 'openid offline_access chatgpt.tokens.use.direct' });
    }
    case 'https://api.openai.com/v1/models':
      assert.equal(new Headers(options.headers).get('authorization'), 'Bearer synthetic-access');
      return Response.json({ models: [{ slug: 'test-model', display_name: 'Test Model', visibility: 'list' }] });
    case 'https://api.openai.com/v1/responses': {
      const body = JSON.parse(options.body);
      assert.equal(body.model, 'test-model');
      assert.equal(body.store, false);
      assert.deepEqual(body.input, [{ role: 'user', content: 'Test page' }]);
      const events = [{ type: 'response.output_text.delta', delta: '{"answer":"42"}' }];
      if (body.instructions !== 'interrupted') events.push({ type: 'response.completed', response: { status: 'completed' } });
      return new Response(events.map(event => 'data: ' + JSON.stringify(event) + '\n\n').join(''),
        { headers: { 'content-type': 'text/event-stream' } });
    }
    case issuer + '/revoke': return new Response(null, { status: 200 });
    default: throw new Error('Unexpected URL in offline test');
    }
  };
  await import(pathToFileURL(helper));
}

async function run(app) {
  const node = join(app, 'Contents/MacOS/CraMaxNode'), helper = join(app, 'Contents/Resources/chatgpt/helper.cjs');
  const directory = await mkdtemp(join(tmpdir(), 'cra-max-test-'));
  const key = randomBytes(32).toString('base64');
  async function request(command, fields = {}) {
    const child = cp.spawn(node, ['--no-addons', '--no-global-search-paths', fileURLToPath(import.meta.url), '--helper', helper],
      { stdio: ['pipe', 'pipe', 'inherit'], timeout: 15000 });
    child.stdin.write(JSON.stringify({ command, key, directory, ...fields }) + '\n');
    const closed = once(child, 'close');
    const output = await child.stdout.toArray();
    const [code] = await closed;
    assert.equal(code, 0);
    return JSON.parse(Buffer.concat(output));
  }
  try {
    assert.equal((await request('status')).connected, false);
    assert.deepEqual(await request('connect'), { connected: true, account: 'test@example.invalid', model: 'test-model' });
    const saved = await readFile(join(directory, 'chatgpt-auth.json'), 'utf8');
    assert.ok(JSON.parse(saved).ciphertext);
    assert.ok(!saved.includes('synthetic') && !saved.includes('test@example.invalid'));
    assert.equal((await request('status', { key: randomBytes(32).toString('base64') })).connected, false);
    assert.equal((await request('status')).model, 'test-model');
    const fields = { model: 'test-model', messages: [{ role: 'user', content: 'Test page' }] };
    assert.deepEqual(await request('answer', fields), { text: '{"answer":"42"}' });
    assert.equal((await request('answer', { ...fields, instructions: 'interrupted' })).code, 'stream_interrupted');
    assert.equal((await request('disconnect')).connected, false);
    assert.equal((await request('answer', fields)).code, 'sign_in_required');
    console.log('ChatGPT Max: simulated OAuth, encrypted session restore, model discovery, response completion and disconnect passed.');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

if (process.argv[2] === '--helper') await mockProvider(process.argv[3]);
else await run(resolve(process.argv[2]));
