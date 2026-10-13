import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const project = process.argv[2];
const apiKey = "0".repeat(64);
const base = "http://127.0.0.1:18787";
writeFileSync(join(project, ".dev.vars"), `API_KEY=${apiKey}\n`);
const child = spawn("wrangler", ["dev", "--local", "--ip", "127.0.0.1",
    "--port", "18787", "--config", join(project, "wrangler.toml")], {
    cwd: project,
    env: { ...process.env, WRANGLER_SEND_METRICS: "false", CI: "true" },
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
});
let output = "";
child.stdout.on("data", (data) => { output += data; });
child.stderr.on("data", (data) => { output += data; });
const exit = once(child, "exit");
try {
    const deadline = Date.now() + 20000;
    while (true) {
        try {
            if ((await fetch(base, { signal: AbortSignal.timeout(500) })).ok) break;
        } catch {}
        assert.equal(child.exitCode, null, output);
        assert.ok(Date.now() < deadline, output);
        await delay(100);
    }
    const target = `${base}/s/${"0".repeat(32)}`;
    const content = "vless://uuid@example.test:443?type=tcp#中文";
    const upload = await fetch(target, {
        method: "PUT",
        headers: { Authorization: `Bearer ${apiKey}` },
        body: content,
    });
    assert.equal(upload.status, 201, output);
    const image = await fetch(target, { headers: { Accept: "text/html" } });
    assert.equal(image.status, 200, output);
    assert.equal(image.headers.get("Content-Type"), "image/png");
    assert.deepEqual(new Uint8Array(await image.arrayBuffer()).slice(0, 8),
        new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]));
    assert.equal(await (await fetch(target)).text(), content);
    console.log("shortlink workerd PNG: passed");
} finally {
    if (child.exitCode === null) process.kill(-child.pid, "SIGTERM");
    const kill = setTimeout(() => {
        if (child.exitCode === null) process.kill(-child.pid, "SIGKILL");
    }, 5000);
    try { await exit; } finally { clearTimeout(kill); }
}
