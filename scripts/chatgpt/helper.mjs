// One request over private pipes. Closing stdin cancels it, including the OAuth callback listener.
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline';
import { createChatGPT, ChatGPTError } from '@siwc/local';

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
const controller = new AbortController();
input.once('close', () => controller.abort());
process.once('SIGTERM', () => controller.abort());

function encryption(key) {
  if (key.length !== 32) throw new Error('Invalid storage key');
  return {
    id: 'cra-keychain-aes256-gcm-v1',
    isAvailable: () => true,
    encrypt(text) {
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', key, iv);
      const data = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
      return Buffer.concat([iv, cipher.getAuthTag(), data]);
    },
    decrypt(bytes) {
      const data = Buffer.from(bytes);
      const cipher = createDecipheriv('aes-256-gcm', key, data.subarray(0, 12));
      cipher.setAuthTag(data.subarray(12, 28));
      return Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString('utf8');
    }
  };
}

input.once('line', async line => {
  let reply;
  try {
    const { command, key, directory, model, reasoningEffort, instructions, messages } = JSON.parse(line);
    const client = createChatGPT({ appName: 'Cra', appId: 'cra-max', storageDir: directory,
      redirectPort: 0, credentialEncryption: encryption(Buffer.from(key, 'base64')) });
    const signal = controller.signal;
    if (command === 'answer') {
      const { text } = await client.streamResponse({ model, reasoningEffort, instructions, input: messages, signal });
      if (Buffer.byteLength(text) > 300_000) throw new Error('Oversized reply');
      reply = { text };
    } else {
      if (command === 'connect') {
        const previous = await client.getSession();
        const pending = !previous.profileId && (await client.listProfiles()).find(profile => profile.pending);
        await client.signIn({ signal, reconsent: true, profileId: pending?.id,
          newProfile: previous.status === 'disconnected' && Boolean(previous.profileId) });
      }
      else if (command === 'disconnect') await client.disconnect();
      else if (command !== 'status') throw new Error('Unknown command');
      const session = await client.getSession();
      reply = { connected: session.status === 'connected', account: session.identity?.email ?? session.identity?.name,
        error: session.error?.message };
      if (session.sharing) {
        try {
          reply.models = await client.listModels({ signal });
          if (!reply.models.length) reply.error = 'Your ChatGPT plan currently offers no models to Cra.';
        } catch (error) {
          if (!(error instanceof ChatGPTError)) throw error;
          reply.error = error.message;
        }
      } else if (reply.connected) {
        reply.error = 'Enable plan sharing when you sign in to use ChatGPT for Max.';
      }
    }
  } catch (error) {
    const effortRejected = error instanceof ChatGPTError && ['reasoning', 'reasoning.effort'].includes(error.param);
    reply = { error: effortRejected ? 'ChatGPT rejected this reasoning effort. Choose another level or Model default in Max settings.'
      : error instanceof ChatGPTError ? error.message : 'ChatGPT could not complete this request.',
      code: error instanceof ChatGPTError ? error.code : undefined };
  }
  process.stdout.write(JSON.stringify(reply));
  input.close();
  process.stdin.destroy();
});
