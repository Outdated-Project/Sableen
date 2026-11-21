#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d)
install -d "$root/DEBIAN" "$root/opt/sableen" "$root/usr/bin" "$root/usr/share/applications"
cp -a build/linux/x64/release/bundle/. "$root/opt/sableen/"
ln -s /opt/sableen/sableen "$root/usr/bin/sableen"
cat > "$root/DEBIAN/control" <<EOF
Package: sableen
Version: $APP_VERSION
Architecture: amd64
Maintainer: Sableen contributors
Depends: libgtk-3-0t64, libmpv2, libepoxy0, libstdc++6, libc6 (>= 2.39)
Description: Sableen short drama player
EOF
cat > "$root/usr/share/applications/sableen.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Sableen
Exec=/usr/bin/sableen
Categories=AudioVideo;Player;
EOF
mkdir -p dist
dpkg-deb --build --root-owner-group "$root" dist/Sableen-ubuntu24-amd64.deb
sudo apt-get install -y ./dist/Sableen-ubuntu24-amd64.deb
python3 tool/ci/verify_assets.py /opt/sableen/data/flutter_assets
xvfb-run -a bash -euc 'sableen & pid=$!; trap "kill $pid" EXIT; timeout 60 xdotool search --sync --onlyvisible --pid "$pid" >/dev/null; kill -0 "$pid"'
