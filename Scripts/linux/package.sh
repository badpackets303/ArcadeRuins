#!/bin/bash
# Runs INSIDE the release container (Scripts/release-linux.sh starts it). /src is the repository,
# read-only; /work a Docker volume with the build tree; /out where the tarball is left.
set -euo pipefail
version=$(awk '/^project\(ArcadeRuins VERSION/ { print $3; exit }' /src/CMakeLists.txt)
arch=$(uname -m)
name="ArcadeRuins-$version-linux-$arch"
git config --global --add safe.directory '*'

echo "━━ GCC $(gcc -dumpversion), glibc $(ldd --version | head -1 | awk '{ print $NF }'), $arch: build, every CTest test"
cmake -S /src -B /work/release -DS1_BUILD_PLUGIN=ON -DCMAKE_BUILD_TYPE=Release > /work/release-configure.log 2>&1 || { tail -30 /work/release-configure.log; exit 1; }
cmake --build /work/release --parallel "$(nproc)" > /work/release-build.log 2>&1 || { grep -E "error|Error" /work/release-build.log | head -40; exit 1; }
ctest --test-dir /work/release --output-on-failure 2>&1 | tail -4
ctest --test-dir /work/release > /dev/null      # the exit status, after the tail above

artefacts=/work/release/Sources/S1Plugin/ArcadeRuins_artefacts/Release
stage=/work/stage/$name
rm -rf /work/stage && mkdir -p "$stage"
cp -R "$artefacts/VST3/Arcade Ruins.vst3" "$stage/"
cp "$artefacts/Standalone/Arcade Ruins" "$stage/arcade-ruins"
strip --strip-unneeded "$stage/arcade-ruins" "$stage/Arcade Ruins.vst3/Contents/"*/*.so
cp /src/LICENSE /src/NOTICE.md "$stage/"

needed=$(objdump -p "$stage/arcade-ruins" "$stage/Arcade Ruins.vst3/Contents/"*/*.so | awk '/NEEDED/ { print $2 }' | sort -u | tr '\n' ' ')
newest=$(objdump -T "$stage/arcade-ruins" "$stage/Arcade Ruins.vst3/Contents/"*/*.so | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)

cat > "$stage/install.sh" <<'INSTALL'
#!/bin/sh
# Installs Arcade Ruins for THIS USER — no root: the VST3 where every Linux host looks for one,
# the standalone in ~/.local/bin, and a menu entry.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.vst3" "$HOME/.local/bin" "$HOME/.local/share/applications"
rm -rf "$HOME/.vst3/Arcade Ruins.vst3"
cp -R "$here/Arcade Ruins.vst3" "$HOME/.vst3/"
cp "$here/arcade-ruins" "$HOME/.local/bin/arcade-ruins"
chmod +x "$HOME/.local/bin/arcade-ruins"
cat > "$HOME/.local/share/applications/arcade-ruins.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Arcade Ruins
Comment=Polyphonic synthesizer
Exec=$HOME/.local/bin/arcade-ruins
Categories=AudioVideo;Audio;Midi;
Terminal=false
DESKTOP
echo "Installed: ~/.vst3/Arcade Ruins.vst3 and ~/.local/bin/arcade-ruins. Rescan plugins in your host."
INSTALL
cat > "$stage/uninstall.sh" <<'UNINSTALL'
#!/bin/sh
# Removes what install.sh placed. Your presets, tunings and settings are NOT touched:
#   ~/.config/BadPackets/Arcade Ruins
rm -rf "$HOME/.vst3/Arcade Ruins.vst3" "$HOME/.local/bin/arcade-ruins" "$HOME/.local/share/applications/arcade-ruins.desktop"
echo "Arcade Ruins is removed. Your presets are still in ~/.config/BadPackets/Arcade Ruins"
UNINSTALL
chmod +x "$stage/install.sh" "$stage/uninstall.sh"

cat > "$stage/README.txt" <<README
Arcade Ruins $version for Linux ($arch) — VST3 plugin and standalone

  ./install.sh      installs for your user: ~/.vst3/Arcade Ruins.vst3, ~/.local/bin/arcade-ruins
  ./uninstall.sh    removes them; your presets in ~/.config/BadPackets/Arcade Ruins stay

Built on Ubuntu 22.04 with GCC $(gcc -dumpversion). Needs glibc ${newest#GLIBC_} or newer, and these libraries
(a desktop with ALSA has them; on Debian/Ubuntu: libasound2 libfreetype6 libfontconfig1):
  $needed

An unofficial port of AudioKit Synth One. MIT — see LICENSE and NOTICE.md.
README

tar -C /work/stage -czf "/out/$name.tar.gz" "$name"
(cd /out && sha256sum "$name.tar.gz" | tee "$name.tar.gz.sha256")
echo "   needs $newest; links: $needed"
echo "✅ /out/$name.tar.gz"
