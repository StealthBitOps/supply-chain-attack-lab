#!/bin/bash
set -e

echo "============================================"
echo "  Supply Chain Attack Lab - Setup"
echo "  MITRE ATT&CK T1195.002"
echo "============================================"
echo ""

command -v node >/dev/null 2>&1 || { echo "[!] Node.js not found. Run: sudo apt install -y nodejs npm"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "[!] npm not found. Run: sudo apt install -y npm"; exit 1; }
command -v verdaccio >/dev/null 2>&1 || { echo "[!] Verdaccio not found. Run: sudo npm install -g verdaccio"; exit 1; }

echo "[*] Prerequisites OK: node $(node --version), npm $(npm --version)"
echo ""

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$LAB_DIR/verdaccio-configs"

rm -rf private-storage public-storage private-htpasswd public-htpasswd

echo "[*] Starting private registry on port 4873..."
verdaccio --config "$LAB_DIR/verdaccio-configs/private-config.yaml" &
PRIVATE_PID=$!
echo "[*] Private registry PID: $PRIVATE_PID"

echo "[*] Starting public registry on port 4874..."
verdaccio --config "$LAB_DIR/verdaccio-configs/public-config.yaml" &
PUBLIC_PID=$!
echo "[*] Public registry PID: $PUBLIC_PID"

echo "[*] Waiting for registries to start..."
sleep 10

for i in {1..10}; do
  if curl -s http://localhost:4873 >/dev/null 2>&1 && curl -s http://localhost:4874 >/dev/null 2>&1; then
    echo "[*] Both registries are up!"
    break
  fi
  sleep 1
done

echo "[*] Creating/authenticating admin user on private registry..."
# DESIGN DECISION: We pass Basic Auth (-u admin:admin123) to make this PUT command idempotent.
# - If the user is new: Verdaccio registers them and returns a token.
# - If the user already exists: Verdaccio authenticates them and returns a token.
# This avoids HTTP 409 'username already registered' conflicts on rebuilds, keeping $PRIVATE_TOKEN valid.
PRIVATE_TOKEN=$(curl -s -u admin:admin123 -X PUT http://localhost:4873/-/user/org.couchdb.user:admin \
  -H "Content-Type: application/json" \
  -d '{"name":"admin","password":"admin123"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

echo "[*] Creating/authenticating attacker user on public registry..."
curl -s -u attacker:attacker123 -X PUT http://localhost:4874/-/user/org.couchdb.user:attacker \
  -H "Content-Type: application/json" \
  -d '{"name":"attacker","password":"attacker123"}' >/dev/null 2>&1

echo "[*] Publishing acme-auth-utils v1.0.0 to private registry..."
cd "$LAB_DIR/packages/legit-auth-utils"

# WORKAROUND: npm 11 has strict requirements for token formatting and ignores standard CLI auth overrides.
# We write the raw token without double quotes to a temporary local .npmrc, which npm natively respects.
echo "//localhost:4873/:_authToken=$PRIVATE_TOKEN" > .npmrc

# Publish the package
npm publish --registry http://localhost:4873 2>/dev/null || echo "[!] Publish failed, verify credentials"

# Clean up the temporary config immediately to maintain clean state
rm -f .npmrc

cd "$LAB_DIR"

echo ""
echo "============================================"
echo "  Lab is READY"
echo "============================================"
echo ""
echo "  Private Registry: http://localhost:4873"
echo "  Public Registry:  http://localhost:4874"
echo "  Vulnerable App:   $LAB_DIR/vulnerable-app/"
echo ""
echo "  Read CHALLENGE.md to begin the attack."
echo "  Run ./teardown-lab.sh when finished."
echo ""
echo "  Registry credentials:"
echo "    Private - admin:admin123"
echo "    Public  - attacker:attacker123"
echo "============================================"
