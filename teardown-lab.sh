#!/bin/bash
echo "[*] Stopping Verdaccio instances..."
pkill -f "verdaccio" 2>/dev/null
pkill -f "node.*server.js" 2>/dev/null
sleep 1
echo "[*] Cleaning up storage..."
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "$LAB_DIR/verdaccio-configs/private-storage"
rm -rf "$LAB_DIR/verdaccio-configs/public-storage"
rm -rf "$LAB_DIR/verdaccio-configs/private-htpasswd"
rm -rf "$LAB_DIR/verdaccio-configs/public-htpasswd"
rm -rf "$LAB_DIR/vulnerable-app/node_modules"
rm -rf "$LAB_DIR/vulnerable-app/package-lock.json"
rm -rf "$LAB_DIR/defenses/defended-app/node_modules"
rm -rf "$LAB_DIR/defenses/defended-app/package-lock.json"
rm -rf "$LAB_DIR/attacker-workspace/"*
echo "[*] Lab torn down. Run ./setup-lab.sh to restart."
