# Supply Chain Attack Challenge: Dependency Confusion

## Scenario

You've discovered that Acme Corp uses an internal npm registry at `http://localhost:4873`.
Your recon has revealed an application that depends on a package called `acme-auth-utils`.
Exploit this.

## Objectives

Capture the following flags from the build server by exploiting a dependency confusion vulnerability:

1. **Hostname** of the build server
2. **Username** of the account running the build
3. **Environment variable keys** that contain secrets (KEY, SECRET, or TOKEN)

Flags are displayed on the monitoring server at `http://127.0.0.1:3000` in the format:
```
[FLAG] hostname=<value>
[FLAG] username=<value>
```

## Rules

- You may NOT access the private registry (port 4873) directly to publish or modify packages.
- You may only use the public registry (port 4874) for your attack.
- The monitoring server (port 3000) is your C2 server. Start it before attacking.
- You may inspect anything in the `vulnerable-app/` directory.
- Your payload must execute automatically during `npm install` with no user interaction.

## Getting Started

1. Start the monitoring server: `node monitoring-server/server.js`
2. Explore `vulnerable-app/` for reconnaissance.
3. Use `attacker-workspace/` to craft your payload.
4. Publish your malicious package to the public registry on port 4874.
5. Trigger the attack by running `npm install` inside `vulnerable-app/`.

## Hints

### Tier 1 (Minimal)

- Look at how npm resolves package versions when the same name exists on multiple registries.
- The `preinstall` lifecycle script runs before dependencies are installed.

### Tier 2 (Moderate)

- The vulnerable app uses an unscoped package name with a `^` version range.
- A higher version number on any reachable registry wins the resolution race.
- npm lifecycle scripts can execute arbitrary Node.js code.

### Tier 3 (Almost the answer)

- Create a package named `acme-auth-utils` at version `99.0.0`.
- Add a `preinstall` script in `package.json` that runs a Node.js file.
- That file should POST system data (hostname, username, env keys) to `http://127.0.0.1:3000/exfil`.
- Publish to `http://localhost:4874` using the attacker credentials.
- Then run `npm install` in `vulnerable-app/` with the public registry as a fallback.
