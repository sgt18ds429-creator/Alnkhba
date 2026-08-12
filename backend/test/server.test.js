import test from 'node:test';
import assert from 'node:assert/strict';

import {
  cleanHistory,
  findImageBlock,
  inlinePart,
  rateLimit,
  requestHandler,
} from '../src/server.js';

test('history is normalized and bounded', () => {
  const input = Array.from({ length: 45 }, (_, index) => ({
    role: index % 2 ? 'model' : 'unexpected',
    parts: [{ text: `message-${index}` }],
  }));
  const result = cleanHistory(input);
  assert.equal(result.length, 40);
  assert.equal(result[0].parts[0].text, 'message-5');
  assert.equal(result[0].role, 'model');
  assert.equal(result[1].role, 'user');
});

test('image response traversal accepts only supported bounded image blocks', () => {
  assert.deepEqual(
    findImageBlock({ steps: [{ content: [{ type: 'image', data: 'YWJj', mime_type: 'image/png' }] }] }),
    { data: 'YWJj', mimeType: 'image/png' },
  );
  assert.equal(
    findImageBlock({ type: 'image', data: 'YWJj', mime_type: 'image/svg+xml' }),
    null,
  );
});

test('inline attachment enforces its MIME allow-list', () => {
  const part = inlinePart('YWJj', 'image/png', ['image/png']);
  assert.deepEqual(part, {
    inline_data: { mime_type: 'image/png', data: 'YWJj' },
  });
  assert.throws(
    () => inlinePart('YWJj', 'text/html', ['image/png']),
    /INVALID_ATTACHMENT_TYPE/,
  );
  assert.throws(
    () => inlinePart('not-base64!', 'image/png', ['image/png']),
    /INVALID_ATTACHMENT_ENCODING/,
  );
});

test('rate limiter rejects calls above the configured window limit', () => {
  const id = `test-${Date.now()}`;
  assert.equal(rateLimit(id, 'ai', 2), true);
  assert.equal(rateLimit(id, 'ai', 2), true);
  assert.equal(rateLimit(id, 'ai', 2), false);
});

test('health route responds without requiring activation', async () => {
  const request = {
    method: 'GET',
    url: '/health',
    headers: {},
  };
  const response = {
    headers: {},
    setHeader(name, value) { this.headers[name] = value; },
    writeHead(status, headers = {}) {
      this.status = status;
      Object.assign(this.headers, headers);
    },
    end(body = '') { this.body = body; },
  };
  await requestHandler(request, response);
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.body), {
    ok: true,
    service: 'eliteradiq-api',
  });
});

test('AI routes reject requests that have no activation credential', async () => {
  const request = {
    method: 'POST',
    url: '/api/chat',
    headers: {},
  };
  const response = {
    headers: {},
    setHeader(name, value) { this.headers[name] = value; },
    writeHead(status, headers = {}) {
      this.status = status;
      Object.assign(this.headers, headers);
    },
    end(body = '') { this.body = body; },
  };

  await requestHandler(request, response);
  assert.equal(response.status, 401);
  assert.equal(JSON.parse(response.body).error, 'invalid_activation');
});

test('public activation gateway validates input before calling Supabase', async () => {
  const request = {
    method: 'POST',
    url: '/api/activate',
    headers: {},
    socket: { remoteAddress: '192.0.2.10' },
    async *[Symbol.asyncIterator]() {
      yield Buffer.from(JSON.stringify({ fullName: 'اسم ناقص' }));
    },
  };
  const response = {
    headers: {},
    setHeader(name, value) { this.headers[name] = value; },
    writeHead(status, headers = {}) {
      this.status = status;
      Object.assign(this.headers, headers);
    },
    end(body = '') { this.body = body; },
  };

  await requestHandler(request, response);
  assert.equal(response.status, 400);
  assert.equal(JSON.parse(response.body).error, 'invalid_activation_request');
});

test('CORS is emitted only for an explicitly allowed origin', async () => {
  const previous = process.env.ALLOWED_ORIGINS;
  process.env.ALLOWED_ORIGINS = 'https://app.example.test';
  try {
    const request = {
      method: 'OPTIONS',
      url: '/api/chat',
      headers: { origin: 'https://app.example.test' },
    };
    const response = {
      headers: {},
      setHeader(name, value) { this.headers[name] = value; },
      writeHead(status, headers = {}) {
        this.status = status;
        Object.assign(this.headers, headers);
      },
      end(body = '') { this.body = body; },
    };

    await requestHandler(request, response);
    assert.equal(response.status, 204);
    assert.equal(
      response.headers['access-control-allow-origin'],
      'https://app.example.test',
    );
  } finally {
    if (previous == null) delete process.env.ALLOWED_ORIGINS;
    else process.env.ALLOWED_ORIGINS = previous;
  }
});
