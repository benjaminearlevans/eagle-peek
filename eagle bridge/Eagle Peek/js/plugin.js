const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { URL } = require("url");

const BRIDGE_VERSION = "1.0.0";
const EAGLE_API_BASE_URL = "http://127.0.0.1:41595";
const DEFAULT_PORT = 41695;
const MAX_PORT = 41710;
const PAIRING_TTL_MS = 10 * 60 * 1000;
const MAX_BODY_BYTES = 12 * 1024 * 1024;

let pluginPath = null;
let server = null;
let bridgePort = null;
let pairing = null;
let devices = {};

function randomToken(byteCount = 24) {
    return crypto.randomBytes(byteCount).toString("base64url");
}

function now() {
    return Date.now();
}

function stateFilePath() {
    return path.join(pluginPath, "bridge-state.json");
}

function loadState() {
    if (!pluginPath) {
        devices = {};
        return;
    }

    try {
        const raw = fs.readFileSync(stateFilePath(), "utf8");
        const parsed = JSON.parse(raw);
        devices = parsed.devices || {};
    } catch {
        devices = {};
    }
}

function saveState() {
    if (!pluginPath) {
        return;
    }

    const state = {
        version: 1,
        devices,
    };
    fs.writeFileSync(stateFilePath(), JSON.stringify(state, null, 2));
}

function localIPv4Addresses() {
    const addresses = [];
    const interfaces = os.networkInterfaces();

    for (const entries of Object.values(interfaces)) {
        for (const entry of entries || []) {
            if (entry.family === "IPv4" && !entry.internal) {
                addresses.push(entry.address);
            }
        }
    }

    return addresses;
}

function bridgeHost() {
    return localIPv4Addresses()[0] || "127.0.0.1";
}

function bridgeBaseURL() {
    return `http://${bridgeHost()}:${bridgePort}`;
}

async function libraryInfo() {
    const info = await eagle.library.info();
    return {
        name: info.name || eagle.library.name || "Eagle Library",
        path: info.path || eagle.library.path || "",
        modificationTime: info.modificationTime || eagle.library.modificationTime || 0,
    };
}

function setText(id, value) {
    const element = document.getElementById(id);
    if (element) {
        element.textContent = value;
    }
}

function setStatus(kind, message) {
    const dot = document.getElementById("statusDot");
    if (dot) {
        dot.className = `dot ${kind}`;
    }
    setText("statusText", message);
}

async function refreshUI() {
    if (!bridgePort) {
        setStatus("", "Starting bridge...");
        return;
    }

    try {
        const library = await libraryInfo();
        const pairingURL = createPairingURL();
        setStatus("ready", "Bridge ready");
        setText("libraryName", library.name);
        setText("bridgeURL", bridgeBaseURL());
        setText("pairingURL", pairingURL);
    } catch (error) {
        setStatus("error", `Bridge running, but Eagle library info is unavailable: ${error.message}`);
        setText("bridgeURL", bridgeBaseURL());
    }
}

function createPairingURL() {
    pairing = {
        code: randomToken(18),
        expiresAt: now() + PAIRING_TTL_MS,
    };

    return `eaglepeek://bridge-pair?baseURL=${encodeURIComponent(bridgeBaseURL())}&code=${encodeURIComponent(pairing.code)}`;
}

function sendJSON(response, statusCode, payload) {
    const data = Buffer.from(JSON.stringify(payload));
    response.writeHead(statusCode, {
        "Content-Type": "application/json",
        "Content-Length": data.length,
        "Cache-Control": "no-store",
    });
    response.end(data);
}

function sendError(response, statusCode, message) {
    sendJSON(response, statusCode, {
        status: "error",
        message,
    });
}

function readRequestBody(request) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        let receivedBytes = 0;

        request.on("data", (chunk) => {
            receivedBytes += chunk.length;
            if (receivedBytes > MAX_BODY_BYTES) {
                reject(new Error("Request body is too large."));
                request.destroy();
                return;
            }
            chunks.push(chunk);
        });

        request.on("end", () => {
            resolve(Buffer.concat(chunks));
        });

        request.on("error", reject);
    });
}

function deviceForRequest(request) {
    const authorization = request.headers.authorization || "";
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    if (!match) {
        return null;
    }

    return devices[match[1]] || null;
}

function requireDevice(request, response) {
    const device = deviceForRequest(request);
    if (!device || device.revokedAt) {
        sendError(response, 401, "Bridge pairing is missing, invalid, or revoked.");
        return null;
    }

    device.lastSeenAt = new Date().toISOString();
    saveState();
    return device;
}

async function handlePairClaim(request, response) {
    if (request.method !== "POST") {
        sendError(response, 405, "Method not allowed.");
        return;
    }

    const body = await readRequestBody(request);
    const payload = JSON.parse(body.toString("utf8") || "{}");

    if (!pairing || pairing.expiresAt < now() || payload.pairingCode !== pairing.code) {
        sendError(response, 401, "Pairing code is invalid or expired.");
        return;
    }

    pairing = null;
    const token = randomToken(32);
    const deviceName = String(payload.deviceName || "iPhone").slice(0, 80);
    const library = await libraryInfo();
    const createdAt = new Date().toISOString();

    devices[token] = {
        deviceName,
        appVersion: String(payload.appVersion || ""),
        createdAt,
        lastSeenAt: createdAt,
        revokedAt: null,
        libraryPath: library.path,
    };
    saveState();

    sendJSON(response, 200, {
        status: "success",
        data: {
            bridgeVersion: BRIDGE_VERSION,
            bridgeBaseURL: bridgeBaseURL(),
            apiBaseURL: `${bridgeBaseURL()}/api/v2/`,
            mediaBaseURL: `${bridgeBaseURL()}/media/v1/`,
            deviceToken: token,
            library,
            capabilities: {
                apiProxy: true,
                mediaProxy: true,
                originalMedia: true,
                rangeRequests: true,
            },
        },
    });
}

function proxiedAPIPath(requestURL) {
    return `${EAGLE_API_BASE_URL}${requestURL.pathname}${requestURL.search}`;
}

async function handleAPIProxy(request, response, requestURL) {
    if (!requireDevice(request, response)) {
        return;
    }

    const body = request.method === "GET" || request.method === "HEAD"
        ? null
        : await readRequestBody(request);
    const headers = {
        Accept: request.headers.accept || "application/json",
    };

    if (request.headers["content-type"]) {
        headers["Content-Type"] = request.headers["content-type"];
    }

    const proxyRequest = http.request(proxiedAPIPath(requestURL), {
        method: request.method,
        headers,
    }, (proxyResponse) => {
        response.writeHead(proxyResponse.statusCode || 502, {
            "Content-Type": proxyResponse.headers["content-type"] || "application/json",
            "Cache-Control": "no-store",
        });
        proxyResponse.pipe(response);
    });

    proxyRequest.on("error", (error) => {
        sendError(response, 502, `Eagle API proxy failed: ${error.message}`);
    });

    if (body) {
        proxyRequest.write(body);
    }
    proxyRequest.end();
}

function sanitizeSegment(value) {
    if (!/^[A-Za-z0-9_-]+$/.test(value)) {
        return null;
    }

    return value;
}

async function mediaCandidatePaths(itemId, variant) {
    const library = await libraryInfo();
    const itemDirectory = path.join(library.path, "images", `${itemId}.info`);
    const files = await fs.promises.readdir(itemDirectory, { withFileTypes: true });
    const normalFiles = files
        .filter((entry) => entry.isFile())
        .map((entry) => entry.name);

    const thumbnails = normalFiles.filter((name) => name.endsWith("_thumbnail.png"));
    const originals = normalFiles.filter((name) => !name.endsWith("_thumbnail.png") && name !== "metadata.json");

    if (variant === "thumbnail" || variant === "preview") {
        return thumbnails.concat(originals).map((name) => path.join(itemDirectory, name));
    }

    return originals.concat(thumbnails).map((name) => path.join(itemDirectory, name));
}

function contentTypeForPath(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    switch (ext) {
    case ".avif": return "image/avif";
    case ".gif": return "image/gif";
    case ".heic": return "image/heic";
    case ".jpeg":
    case ".jpg": return "image/jpeg";
    case ".mp4": return "video/mp4";
    case ".png": return "image/png";
    case ".webp": return "image/webp";
    default: return "application/octet-stream";
    }
}

async function firstExistingPath(paths) {
    for (const candidate of paths) {
        try {
            const stat = await fs.promises.stat(candidate);
            if (stat.isFile()) {
                return { filePath: candidate, stat };
            }
        } catch {
            // Try the next candidate.
        }
    }

    return null;
}

function parseRange(rangeHeader, fileSize) {
    if (!rangeHeader) {
        return null;
    }

    const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader);
    if (!match) {
        return null;
    }

    const start = match[1] ? Number(match[1]) : 0;
    const end = match[2] ? Number(match[2]) : fileSize - 1;
    if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || end >= fileSize) {
        return null;
    }

    return { start, end };
}

async function handleMedia(request, response, requestURL) {
    if (!requireDevice(request, response)) {
        return;
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
        sendError(response, 405, "Method not allowed.");
        return;
    }

    const parts = requestURL.pathname.split("/").filter(Boolean);
    const itemId = sanitizeSegment(parts[3] || "");
    const variant = parts[4];
    if (!itemId || !["thumbnail", "preview", "original"].includes(variant)) {
        sendError(response, 400, "Invalid media request.");
        return;
    }

    const match = await firstExistingPath(await mediaCandidatePaths(itemId, variant));
    if (!match) {
        sendError(response, 404, "Media file was not found.");
        return;
    }

    const { filePath, stat } = match;
    const range = parseRange(request.headers.range, stat.size);
    const headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "private, max-age=86400",
        "Content-Type": contentTypeForPath(filePath),
    };

    if (range) {
        headers["Content-Length"] = range.end - range.start + 1;
        headers["Content-Range"] = `bytes ${range.start}-${range.end}/${stat.size}`;
        response.writeHead(206, headers);
        if (request.method !== "HEAD") {
            fs.createReadStream(filePath, { start: range.start, end: range.end }).pipe(response);
        } else {
            response.end();
        }
        return;
    }

    headers["Content-Length"] = stat.size;
    response.writeHead(200, headers);
    if (request.method !== "HEAD") {
        fs.createReadStream(filePath).pipe(response);
    } else {
        response.end();
    }
}

async function handleRequest(request, response) {
    try {
        const requestURL = new URL(request.url, bridgeBaseURL());

        if (requestURL.pathname === "/health") {
            sendJSON(response, 200, {
                status: "success",
                data: {
                    bridgeVersion: BRIDGE_VERSION,
                    library: await libraryInfo(),
                },
            });
            return;
        }

        if (requestURL.pathname === "/pair/claim") {
            await handlePairClaim(request, response);
            return;
        }

        if (requestURL.pathname.startsWith("/api/v2/")) {
            await handleAPIProxy(request, response, requestURL);
            return;
        }

        if (requestURL.pathname.startsWith("/media/v1/items/")) {
            await handleMedia(request, response, requestURL);
            return;
        }

        sendError(response, 404, "Bridge route was not found.");
    } catch (error) {
        sendError(response, 500, error.message);
    }
}

function listenOnPort(port) {
    return new Promise((resolve, reject) => {
        const candidate = http.createServer((request, response) => {
            handleRequest(request, response);
        });

        candidate.once("error", reject);
        candidate.listen(port, "0.0.0.0", () => {
            candidate.removeAllListeners("error");
            resolve(candidate);
        });
    });
}

async function startBridge() {
    if (server) {
        await refreshUI();
        return;
    }

    for (let port = DEFAULT_PORT; port <= MAX_PORT; port += 1) {
        try {
            server = await listenOnPort(port);
            bridgePort = port;
            await refreshUI();
            return;
        } catch {
            server = null;
            bridgePort = null;
        }
    }

    setStatus("error", `Could not start bridge on ports ${DEFAULT_PORT}-${MAX_PORT}.`);
}

eagle.onPluginCreate((plugin) => {
    pluginPath = plugin.path;
    loadState();
    startBridge();
});

eagle.onPluginRun(() => {
    refreshUI();
});

eagle.onPluginShow(() => {
    refreshUI();
});

eagle.onLibraryChanged(() => {
    refreshUI();
});

window.addEventListener("DOMContentLoaded", () => {
    const copyButton = document.getElementById("copyButton");
    if (copyButton) {
        copyButton.addEventListener("click", async () => {
            const pairingURL = document.getElementById("pairingURL")?.textContent || "";
            await navigator.clipboard.writeText(pairingURL);
            copyButton.textContent = "Copied";
            setTimeout(() => {
                copyButton.textContent = "Copy Pairing Link";
            }, 1400);
        });
    }

    refreshUI();
});
