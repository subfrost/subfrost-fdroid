#!/bin/bash
set -e

FDROID_DIR="/var/www/fdroid"
REPO_DIR="$FDROID_DIR/repo"
KEYSTORE_DIR="$FDROID_DIR/keystore"
METADATA_DIR="$FDROID_DIR/metadata"

echo "=== Subfrost F-Droid Repository Server ==="
echo "Starting initialization..."

# Create required directories
mkdir -p "$REPO_DIR" "$KEYSTORE_DIR" "$METADATA_DIR" "$FDROID_DIR/unsigned"

# Initialize keystore if not present
if [ ! -f "$KEYSTORE_DIR/fdroid.keystore" ]; then
    echo "Generating new F-Droid signing keystore..."

    KEYSTORE_PASS="${FDROID_KEYSTORE_PASS:-$(openssl rand -base64 32)}"
    KEY_PASS="${FDROID_KEY_PASS:-$KEYSTORE_PASS}"

    keytool -genkey -v \
        -keystore "$KEYSTORE_DIR/fdroid.keystore" \
        -alias fdroid \
        -keyalg RSA \
        -keysize 4096 \
        -validity 10000 \
        -storepass "$KEYSTORE_PASS" \
        -keypass "$KEY_PASS" \
        -dname "CN=Subfrost, OU=F-Droid Repository, O=Subfrost, L=Internet, C=XX"

    # Extract and display fingerprint
    echo ""
    echo "=== IMPORTANT: Repository Fingerprint ==="
    keytool -list -v -keystore "$KEYSTORE_DIR/fdroid.keystore" \
        -alias fdroid -storepass "$KEYSTORE_PASS" 2>/dev/null | grep -A1 "SHA256:"
    echo "==========================================="
    echo ""
    echo "Save this fingerprint! Users need it to verify the repository."

    # Save passwords to file (for CI access)
    echo "FDROID_KEYSTORE_PASS=$KEYSTORE_PASS" > "$KEYSTORE_DIR/.env"
    echo "FDROID_KEY_PASS=$KEY_PASS" >> "$KEYSTORE_DIR/.env"
    chmod 600 "$KEYSTORE_DIR/.env"
fi

# Generate config.py from config.yml for fdroidserver
cat > "$FDROID_DIR/config.py" << 'PYEOF'
#!/usr/bin/env python3
# Auto-generated F-Droid configuration

import os

# Repository settings
repo_url = os.environ.get('FDROID_REPO_URL', 'https://f-droid.subfrost.io/fdroid/repo')
repo_name = 'Subfrost F-Droid Repository'
repo_description = '''Official F-Droid repository for Subfrost applications.
This repository contains Subtun and other Subfrost Android apps.'''

# Keystore configuration
keystore = 'keystore/fdroid.keystore'
keystorepass = os.environ.get('FDROID_KEYSTORE_PASS', 'changeme')
keypass = os.environ.get('FDROID_KEY_PASS', 'changeme')
keydname = 'CN=Subfrost, OU=F-Droid Repository, O=Subfrost, L=Internet, C=XX'

# Repository key alias
repo_keyalias = 'fdroid'

# Accept all signature algorithms
allow_disabled_algorithms = True

# Archive settings
archive_older = 0
PYEOF

# Initialize repo if index doesn't exist
if [ ! -f "$REPO_DIR/index-v1.jar" ]; then
    echo "Initializing F-Droid repository..."
    cd "$FDROID_DIR"
    fdroid init || true

    # Update if there are any APKs
    if ls "$REPO_DIR"/*.apk 1>/dev/null 2>&1; then
        echo "Found APKs, updating repository..."
        fdroid update --create-metadata --allow-disabled-algorithms
    fi
fi

# Generate landing page
cat > "$FDROID_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Subfrost F-Droid Repository</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 2rem;
        }
        .container {
            max-width: 600px;
            text-align: center;
        }
        h1 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        .subtitle {
            color: #8892b0;
            margin-bottom: 2rem;
        }
        .repo-url {
            background: rgba(255,255,255,0.1);
            border-radius: 8px;
            padding: 1rem;
            margin: 1.5rem 0;
            word-break: break-all;
            font-family: monospace;
            font-size: 0.9rem;
        }
        .repo-url a {
            color: #00d9ff;
            text-decoration: none;
        }
        .instructions {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 1.5rem;
            margin: 1.5rem 0;
            text-align: left;
        }
        .instructions h3 {
            color: #00ff88;
            margin-bottom: 1rem;
        }
        .instructions ol {
            padding-left: 1.5rem;
        }
        .instructions li {
            margin-bottom: 0.5rem;
            color: #ccd6f6;
        }
        .fingerprint {
            background: #0a0a14;
            border: 1px solid #333;
            border-radius: 8px;
            padding: 1rem;
            margin: 1rem 0;
            font-family: monospace;
            font-size: 0.7rem;
            word-break: break-all;
            color: #00ff88;
        }
        .btn {
            display: inline-block;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            color: #000;
            padding: 0.75rem 1.5rem;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            margin-top: 1rem;
            transition: transform 0.2s;
        }
        .btn:hover {
            transform: scale(1.05);
        }
        footer {
            margin-top: 2rem;
            color: #495670;
            font-size: 0.85rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Subfrost</h1>
        <p class="subtitle">Official F-Droid Repository</p>

        <div class="repo-url">
            <a href="fdroidrepos://f-droid.subfrost.io/fdroid/repo?fingerprint=FINGERPRINT_PLACEHOLDER">
                https://f-droid.subfrost.io/fdroid/repo
            </a>
        </div>

        <div class="instructions">
            <h3>How to Add This Repository</h3>
            <ol>
                <li>Open the F-Droid app on your Android device</li>
                <li>Go to Settings → Repositories</li>
                <li>Tap the + button to add a new repository</li>
                <li>Enter the repository URL shown above</li>
                <li>Verify the fingerprint matches below</li>
            </ol>
        </div>

        <div class="fingerprint">
            <strong>SHA-256 Fingerprint:</strong><br>
            <span id="fingerprint">Loading...</span>
        </div>

        <a href="fdroidrepos://f-droid.subfrost.io/fdroid/repo" class="btn">
            Open in F-Droid
        </a>

        <footer>
            <p>Powered by Subfrost • <a href="https://subfrost.io" style="color: #00d9ff;">subfrost.io</a></p>
        </footer>
    </div>
</body>
</html>
HTMLEOF

echo "Initialization complete."
echo ""

# Execute the main command (nginx)
exec "$@"
