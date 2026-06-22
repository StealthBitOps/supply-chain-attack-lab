# Supply Chain Attack Lab: Dependency Confusion

A hands-on vulnerable lab that teaches dependency confusion attacks and defenses.
Maps to MITRE ATT&CK T1195.002 (Supply Chain Compromise: Compromise Software Supply Chain).

## What This Lab Teaches

- How npm resolves packages across multiple registries
- How attackers exploit unscoped package names to inject malicious code
- How preinstall scripts execute arbitrary code during `npm install`
- Three concrete defenses: scoped packages, registry pinning, lockfile integrity

## Prerequisites

- Debian/Kali Linux (tested on Kali rolling)
- Node.js 18+ and npm
- Git

## Quickstart

```bash
git clone <this-repo-url>
cd supply-chain-lab
./setup-lab.sh
```

Once setup completes, read `CHALLENGE.md` to begin the attack.

## Tracks

### Attacker Track

Read `CHALLENGE.md` for the scenario and objectives. Your goal is to
exploit the vulnerable application's dependency resolution and capture
flags from the monitoring server.

### Defender Track

After completing (or reading) the attack, explore `defenses/` to see
how scoped packages, registry pinning, and lockfile integrity each
prevent the attack at different layers.

Full walkthroughs for both tracks are in `SOLUTION.md`.

## Teardown

```bash
./teardown-lab.sh
```

This stops all background processes, removes registry storage, and
cleans up node_modules.

## Architecture Notes: Idempotent Setup Scripts

To ensure this lab can be torn down and rebuilt endlessly without failure:
- **The Challenge:** Directly calling the CouchDB PUT API endpoint on Verdaccio to register a user fails with a `409 Conflict` on subsequent runs once the database storage exists.
- **The Solution:** We supply HTTP Basic Authentication (`-u username:password`) in the `curl` request. Verdaccio detects the existing user, validates the password, and gracefully returns a valid session token instead of failing, keeping the automated `npm publish` flow active.

## Real-World Context

- **Birsan 2021**: Alex Birsan disclosed dependency confusion across
  Apple, Microsoft, and PayPal, earning $130,000+ in bug bounties.
  The technique requires no special access - only knowledge of an
  internal package name.

- **TeamPCP/PurpleHaze 2026**: Chained dependency confusion into full
  AWS account compromise, infecting 66+ npm packages in a coordinated
  campaign (Feb-Mar 2026).

This lab reproduces the core technique in a safe, isolated environment.

## License

For educational use only. Do not use these techniques against systems
you do not own or have explicit permission to test.

## Troubleshooting

### Private Package Publish Fails (E404 or E401)
If your `setup-lab.sh` runs successfully but `npm view acme-auth-utils --registry http://localhost:4873` returns a `404 Not Found` error, your package manager (particularly npm 11+) may have rejected the automated token.

To resolve this manually:
1. Navigate to the package directory:
   ```bash
   cd packages/legit-auth-utils
   ```
2. Log in using legacy authentication:
   ```bash
   npm login --registry http://localhost:4873 --auth-type=legacy
   ```
   * credentials: `admin` / `admin123`
3. Publish manually:
   ```bash
   npm publish --registry http://localhost:4873
   ```
## Developer Setup: Pushing via SSH

If you are contributing to this repository or pushing updates from a virtual machine (such as Kali Linux), it is highly recommended to use SSH keys instead of HTTPS to avoid credential prompt loops.

### 1. Generate an ED25519 Key
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

### 2. Add the Public Key to GitHub
Print your public key and copy it:
```bash
cat ~/.ssh/id_ed25519.pub
```
Add the copied text under **GitHub Settings -> SSH and GPG keys -> New SSH Key**.

### 3. Switch Remote URL from HTTPS to SSH
If Git is still prompting you for a username and password, update your repository's remote URL to use SSH format:
```bash
git remote set-url origin git@github.com:SSH-CLONE-LINK.git
```

### 4. Push Code Securely
```bash
git push -u origin main
```
