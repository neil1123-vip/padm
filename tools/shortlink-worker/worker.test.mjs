import assert from "node:assert/strict";
import worker from "./worker.js";
import jsQR from "jsqr";
import { PNG } from "pngjs";

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
const send = (method = "GET", body, key = apiKey, bindings = env, target = url, accept = "") =>
    worker.fetch(new Request(target, {
        method, body,
        headers: { ...(key ? { Authorization: `Bearer ${key}` } : {}), Accept: accept },
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
for (const [target, accept] of [
    [url, "text/html,application/xhtml+xml"],
    [url, "TEXT/HTML;q=0.8"],
    [url, "text/html ,text/plain"],
    [`${url}?format=png`, "text/html;q=0"],
]) {
    result = await send("GET", undefined, "", env, target, accept);
    assert.equal(result.status, 200);
    assert.equal(result.headers.get("Content-Type"), "image/png");
    assert.equal(result.headers.get("Cache-Control"), "no-store");
    assert.equal(result.headers.get("Vary"), "Accept");
    assert.equal(result.headers.get("Referrer-Policy"), "no-referrer");
    const image = PNG.sync.read(Buffer.from(await result.arrayBuffer()));
    assert.equal(image.width, image.height);
    const decoded = jsQR(new Uint8ClampedArray(image.data), image.width, image.height);
    assert.equal(decoded?.data, content);
    assert.equal(image.width, (17 + 4 * decoded.version + 8) * 4);
}
assert.equal(await (await send("GET", undefined, "", env, `${url}?format=text`, "text/html")).text(), content);
for (const accept of ["text/plain,text/html;q=0", "text/html; q=0.000", "text/html-other"]) {
    result = await send("GET", undefined, "", env, url, accept);
    assert.equal(result.headers.get("Content-Type"), "text/plain; charset=utf-8");
    assert.equal(await result.text(), content);
}
const longProtocol = `vless://uuid@example.test:443?type=xhttp&extra=${"x".repeat(1800)}#中文`;
const boundaryProtocol = longProtocol + "x".repeat(2953 - new TextEncoder().encode(longProtocol).length);
for (const protocol of [longProtocol, boundaryProtocol]) {
    await send("PUT", protocol);
    result = await send("GET", undefined, "", env, url, "text/html");
    assert.equal(result.status, 200);
    const image = PNG.sync.read(Buffer.from(await result.arrayBuffer()));
    const decoded = jsQR(new Uint8ClampedArray(image.data), image.width, image.height);
    assert.equal(decoded?.data, protocol);
    assert.equal(image.width, image.height);
    assert.equal(image.width, (17 + 4 * decoded.version + 8) * 4);
}
await send("PUT", `${boundaryProtocol}x`);
result = await send("GET", undefined, "", env, `${url}?format=png`);
assert.equal(result.status, 422);
assert.match(await result.text(), /format=text/);
assert.equal(await (await send()).text(), `${boundaryProtocol}x`);
await send("PUT", content);
assert.equal((await send("PUT", "")).status, 400);
assert.equal((await send("PUT", " ")).status, 400);
assert.equal((await send("PUT", new Uint8Array([255]))).status, 400);
assert.equal((await send("PUT", "界".repeat(43691))).status, 413);
assert.equal(values.get(id), content);
assert.equal((await send("PUT", "x".repeat(131072))).status, 201);
assert.equal((await send("PUT", "x".repeat(131073))).status, 413);
assert.equal(values.get(id).length, 131072);
result = await send("GET", undefined, "", env, `${url}?format=png`);
assert.equal(result.status, 422);
assert.match(await result.text(), /format=text/);
assert.equal((await send()).status, 200);
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
