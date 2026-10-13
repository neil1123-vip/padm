import assert from "node:assert/strict";
import worker from "./worker.js";

const id = "0123456789abcdef0123456789abcdef";
const url = `https://short.example.test/s/${id}`;
const apiKey = "a".repeat(64);
const values = new Map();
const env = {
    API_KEY: apiKey,
    KV: {
        async get(key) { return values.get(key) ?? null; },
        async put(key, value) { values.set(key, value); },
        async delete(key) { values.delete(key); },
    },
};
const send = (method = "GET", body, key = apiKey, bindings = env, target = url) =>
    worker.fetch(new Request(target, {
        method, body,
        headers: key ? { Authorization: `Bearer ${key}` } : {},
    }), bindings);

for (const method of ["PUT", "DELETE"]) {
    assert.equal((await send(method, method === "PUT" ? "node" : undefined, "")).status, 401);
    assert.equal((await send(method, method === "PUT" ? "node" : undefined, "wrong")).status, 401);
}
assert.equal(values.size, 0);
assert.equal((await send()).status, 404);
const content = "vless://uuid@example.test:443#中文\nvmess://payload\n";
let result = await send("PUT", content);
assert.equal(result.status, 201);
assert.equal(await result.text(), `${url}\n`);
result = await send("GET", undefined, "");
assert.equal(await result.text(), content);
assert.equal(result.headers.get("Content-Type"), "text/plain; charset=utf-8");
assert.equal(result.headers.get("Cache-Control"), "no-store");
assert.equal((await send("PUT", "")).status, 400);
assert.equal((await send("PUT", " ")).status, 400);
assert.equal((await send("PUT", new Uint8Array([255]))).status, 400);
assert.equal((await send("PUT", "界".repeat(43691))).status, 413);
assert.equal(values.get(id), content);
assert.equal((await send("PUT", "x".repeat(131072))).status, 201);
assert.equal((await send("PUT", "x".repeat(131073))).status, 413);
assert.equal(values.get(id).length, 131072);
assert.equal((await send("DELETE")).status, 200);
assert.equal((await send()).status, 404);
for (const method of ["GET", "PUT", "DELETE"]) {
    const body = method === "PUT" ? "node" : undefined;
    assert.equal((await send(method, body, apiKey, { API_KEY: apiKey })).status, 503);
    const broken = { API_KEY: apiKey, KV: {
        get() { throw new Error("private storage details"); },
        put() { throw new Error("private storage details"); },
        delete() { throw new Error("private storage details"); },
    } };
    result = await send(method, body, apiKey, broken);
    assert.equal(result.status, 503);
    assert.equal(await result.text(), "Storage unavailable\n");
}
assert.equal((await send("PUT", "node", apiKey, env, "https://short.example.test/s/weak")).status, 404);
assert.equal((await send("POST", "node")).status, 404);
console.log("shortlink-worker: passed");
