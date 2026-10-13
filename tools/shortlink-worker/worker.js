import qrImage from "qr-image";

const MAX_BODY_BYTES = 128 * 1024;
const MAX_QR_BYTES = 2953;
const SHORT_PATH = /^\/s\/([0-9a-f]{32})$/;

function response(body, status = 200, contentType = "text/plain; charset=utf-8") {
    return new Response(body, {
        status,
        headers: {
            "Content-Type": contentType,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer",
            "Vary": "Accept",
        },
    });
}

function authorized(request, env) {
    const expected = env.API_KEY;
    const actual = request.headers.get("Authorization") || "";
    return /^[A-Za-z0-9_-]{32,128}$/.test(expected || "") && actual === `Bearer ${expected}`;
}

export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const match = url.pathname.match(SHORT_PATH);

        if (request.method === "GET" && url.pathname === "/") {
            return response("ok\n");
        }
        if (!match || !["GET", "PUT", "DELETE"].includes(request.method)) {
            return response("Not found\n", 404);
        }
        if (request.method !== "GET" && !authorized(request, env)) {
            return response("Unauthorized\n", 401);
        }
        if (!env.KV) {
            return response("Storage unavailable\n", 503);
        }
        try {
            if (request.method === "GET") {
                const value = await env.KV.get(match[1]);
                if (value === null) return response("Not found\n", 404);
                if (url.searchParams.get("format") === "png" ||
                    (url.searchParams.get("format") !== "text" &&
                     (request.headers.get("Accept") || "").split(",").some((type) =>
                         /^\s*text\/html\s*(?:;|$)/i.test(type) &&
                         !/;\s*q\s*=\s*0(?:\.0*)?\s*(?:;|$)/i.test(type)))) {
                    if (new TextEncoder().encode(value).length > MAX_QR_BYTES) {
                        return response("完整协议超过单张二维码容量；在短链后加 ?format=text 获取文本并复制导入。\n", 422);
                    }
                    const image = response(qrImage.imageSync(value, {
                        type: "png", ec_level: "L", size: 8, margin: 4,
                    }), 200, "image/png");
                    image.headers.set("Content-Disposition", 'inline; filename="padm-node.png"');
                    return image;
                }
                return response(value);
            }
            if (request.method === "DELETE") {
                await env.KV.delete(match[1]);
                return response("Deleted\n");
            }
            if (!request.body) {
                return response("Empty payload\n", 400);
            }
            const reader = request.body.getReader();
            const decoder = new TextDecoder("utf-8", { fatal: true });
            let body = "";
            let size = 0;
            try {
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    size += value.byteLength;
                    if (size > MAX_BODY_BYTES) {
                        await reader.cancel();
                        return response("Payload too large\n", 413);
                    }
                    body += decoder.decode(value, { stream: true });
                }
                body += decoder.decode();
            } catch {
                return response("Invalid payload\n", 400);
            }
            if (!body.trim()) {
                return response("Empty payload\n", 400);
            }
            await env.KV.put(match[1], body);
            return response(`${url.origin}${url.pathname}\n`, 201);
        } catch {
            return response("Storage unavailable\n", 503);
        }
    },
};
