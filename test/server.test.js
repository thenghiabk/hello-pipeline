const test = require('node:test');
const assert = require('node:assert');
const createServer = require('../server');

function startServer() {
    return new Promise((resolve) => {
        const server = createServer().listen(0, '127.0.0.1', () =>
            resolve(server));
    });
}

test('GET / should return Hello World', async () => {
    const server = await startServer();
    try {
        const { port } = server.address();
        const res = await fetch(`http://127.0.0.1:${port}/`);
        const body = await res.text();
        assert.strictEqual(res.status, 200);
        assert.ok(body.includes('Hello World'), `Expected "Hello World" in response, got: ${body}`);
    } finally {
        server.close();
        server.closeAllConnections();
    }
});

test('GET /health should return status ok', async () => {
    const server = await startServer();
    try {
        const { port } = server.address();
        const res = await fetch(`http://127.0.0.1:${port}/health`);
        const body = await res.json();
        assert.strictEqual(res.status, 200);
        assert.deepStrictEqual(body, { status: 'ok' });
    } finally {
        server.close();
        server.closeAllConnections();
    }
});

