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

echo "Checking for latest release of $REPO_OWNER/$REPO_NAME..."

# 1. Fetch latest version tag
LATEST_TAG_RAW=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | grep "tag_name" | cut -d '"' -f 4)
VERSION=${LATEST_TAG_RAW#v}

if [ -z "$VERSION" ]; then
    echo "Error: Could not fetch version."
    exit 1
fi
echo "Latest version is: $VERSION"

# 2. Define Architectures (UpstreamName:DebianName)
ARCHS=("x86_64:amd64" "aarch64:arm64")

# 3. Process each architecture
for PAIR in "${ARCHS[@]}"; do
    UPSTREAM_ARCH="${PAIR%%:*}"
    DEB_ARCH="${PAIR##*:}"
    
    echo "--- Processing $DEB_ARCH ($UPSTREAM_ARCH) ---"

    BUILD_DIR="build/${PACKAGE_NAME}_${DEB_ARCH}"
    mkdir -p "$BUILD_DIR/DEBIAN" "$BUILD_DIR/usr/bin" "$BUILD_DIR/usr/share/keyrings" "$BUILD_DIR/etc/apt/sources.list.d"
    mkdir -p "pool/main/m/$PACKAGE_NAME"

    DEB_FILENAME="${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
    DEB_PATH="pool/main/m/$PACKAGE_NAME/$DEB_FILENAME"

    if [ -f "$DEB_PATH" ]; then
        echo "Package $DEB_FILENAME already exists. Skipping."
        rm -rf "$BUILD_DIR"
        continue
    fi

    # Download Binary
    DOWNLOAD_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/${LATEST_TAG_RAW}/edit-${VERSION}-${UPSTREAM_ARCH}-linux-gnu.tar.zst"
    
    if curl -f -L -o temp.tar.zst "$DOWNLOAD_URL"; then
        # Extract Binary
        tar -I zstd -xvf temp.tar.zst --strip-components=1 -C "$BUILD_DIR/usr/bin/"
        mv "$BUILD_DIR/usr/bin/edit" "$BUILD_DIR/usr/bin/$PACKAGE_NAME"
        chmod +x "$BUILD_DIR/usr/bin/$PACKAGE_NAME"
        rm temp.tar.zst

        # Embed Repo Config (Bootstrapping)
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

        # Build Deb
        dpkg-deb --build "$BUILD_DIR" "$DEB_PATH"
        rm -rf "$BUILD_DIR"
    else
        echo "Warning: Download failed for $UPSTREAM_ARCH."
    fi
done

# 4. Generate Repo Metadata
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

# 5. Sign Release
rm -f Release.gpg InRelease
gpg --batch --yes --armor --detach-sign --output Release.gpg Release
gpg --batch --yes --clearsign --output InRelease Release
