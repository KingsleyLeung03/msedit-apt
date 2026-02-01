#!/bin/bash
set -e

# --- Configuration ---
REPO_OWNER="microsoft"
REPO_NAME="edit"
PACKAGE_NAME="msedit"
MAINTAINER_NAME="Kingsley Leung"
EMAIL="kingsleyleung2003@outlook.com"
GITHUB_USER="KingsleyLeung03"
# ---------------------

echo "Fetching release info for $REPO_OWNER/$REPO_NAME..."

RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest")
LATEST_TAG_RAW=$(echo "$RELEASE_JSON" | jq -r .tag_name)
VERSION=${LATEST_TAG_RAW#v}

if [ -z "$VERSION" ] || [ "$VERSION" == "null" ]; then
    echo "Error: Could not fetch version."
    exit 1
fi
echo "Latest version is: $VERSION"

ARCHS=("x86_64:amd64" "aarch64:arm64")

for PAIR in "${ARCHS[@]}"; do
    UPSTREAM_ARCH="${PAIR%%:*}"
    DEB_ARCH="${PAIR##*:}"
    
    echo "--- Processing $DEB_ARCH ($UPSTREAM_ARCH) ---"

    BUILD_DIR="build/${PACKAGE_NAME}_${DEB_ARCH}"
    TEMP_EXTRACT="build/temp_${DEB_ARCH}" # Temp folder for safe extraction

    # Clean previous runs
    rm -rf "$BUILD_DIR" "$TEMP_EXTRACT"

    mkdir -p "$BUILD_DIR/DEBIAN" "$BUILD_DIR/usr/bin" "$BUILD_DIR/usr/share/keyrings" "$BUILD_DIR/etc/apt/sources.list.d"
    mkdir -p "pool/main/m/$PACKAGE_NAME"
    mkdir -p "$TEMP_EXTRACT"

    DEB_FILENAME="${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
    DEB_PATH="pool/main/m/$PACKAGE_NAME/$DEB_FILENAME"

    if [ -f "$DEB_PATH" ]; then
        echo "Package $DEB_FILENAME already exists. Skipping."
        rm -rf "$BUILD_DIR" "$TEMP_EXTRACT"
        continue
    fi

    # Dynamic URL Discovery
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name | contains(\"${UPSTREAM_ARCH}-linux-gnu.tar.zst\")) | .browser_download_url")

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo "Warning: No matching asset found for $UPSTREAM_ARCH. Skipping."
        rm -rf "$BUILD_DIR" "$TEMP_EXTRACT"
        continue
    fi

    echo "Downloading from $DOWNLOAD_URL..."
    
    if curl -f -L -o temp.tar.zst "$DOWNLOAD_URL"; then
        
        # [FIX] Robust Extraction: 
        # 1. Extract to temp folder (no strip)
        tar -I zstd -xvf temp.tar.zst -C "$TEMP_EXTRACT"
        
        # 2. Find the binary named 'edit' anywhere inside
        FOUND_BIN=$(find "$TEMP_EXTRACT" -type f -name "edit" | head -n 1)

        if [ -z "$FOUND_BIN" ]; then
            echo "Error: Could not find 'edit' binary in the archive!"
            exit 1
        fi

        # 3. Move it to the build dir
        mv "$FOUND_BIN" "$BUILD_DIR/usr/bin/$PACKAGE_NAME"
        chmod +x "$BUILD_DIR/usr/bin/$PACKAGE_NAME"
        
        # Cleanup temp
        rm temp.tar.zst
        rm -rf "$TEMP_EXTRACT"

        # Embed Repo Config
        if [ -f "public.key" ]; then
            cp public.key "$BUILD_DIR/usr/share/keyrings/msedit-archive-keyring.gpg"
            chmod 644 "$BUILD_DIR/usr/share/keyrings/msedit-archive-keyring.gpg"
            echo "deb [signed-by=/usr/share/keyrings/msedit-archive-keyring.gpg] https://$GITHUB_USER.github.io/msedit-apt ./" > "$BUILD_DIR/etc/apt/sources.list.d/msedit.list"
            chmod 644 "$BUILD_DIR/etc/apt/sources.list.d/msedit.list"
        fi

        # Create Control File
        SIZE=$(du -s "$BUILD_DIR/usr" | cut -f1)
        cat <<EOF > "$BUILD_DIR/DEBIAN/control"
Package: $PACKAGE_NAME
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: $MAINTAINER_NAME <$EMAIL>
Installed-Size: $SIZE
Section: editors
Priority: optional
Description: Microsoft Edit (Unofficial Auto-Build)
 A modern, modeless text editor for the command line.
 This package automatically configures the APT repository for updates.
EOF

        dpkg-deb --build "$BUILD_DIR" "$DEB_PATH"
        rm -rf "$BUILD_DIR"
    else
        echo "Download failed."
    fi
done

# --- REPO METADATA & SIGNING ---

if [ -z "$GPG_PRIVATE_KEY" ]; then
    echo "Error: GPG_PRIVATE_KEY secret is missing!"
    exit 1
fi
echo "$GPG_PRIVATE_KEY" | gpg --import --batch --yes

dpkg-scanpackages --multiversion pool > Packages
gzip -k -f Packages

cat <<EOF > Release
Origin: MsEdit Unofficial
Label: MsEdit
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Unofficial repository for Microsoft Edit
Date: $(date -R)
EOF
apt-ftparchive release . >> Release

# Clean previous signatures
rm -f Release.gpg InRelease

# Sign
gpg --batch --yes --pinentry-mode loopback --armor --detach-sign --output Release.gpg Release
gpg --batch --yes --pinentry-mode loopback --clearsign --output InRelease Release

echo "Update complete."
