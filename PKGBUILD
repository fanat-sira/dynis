pkgname=dynis
pkgver=1.0.12
pkgrel=1
_srcdir=dynis-1.0.12
pkgdesc="A dynamic island for Hyprland using Quickshell"
arch=('x86_64')
url="https://github.com/fanat-sira/dynis"
license=('GPL-3.0-or-later')
depends=(
    'glib2'
    'qt6-base'
    'qt6-declarative'
    'qt6-connectivity'
    'qt6-svg'
    'hyprland'
    'wireplumber'
    'libpulse'
    'brightnessctl'
    'upower'
    'bluez'
    'bluez-utils'
    'quickshell'
)
makedepends=('cmake' 'pkgconf')
options=('!debug')
optdepends=(
    'cava: for audio visualizer'
    'imagemagick: for wallpaper thumbnails'
    'networkmanager: for wifi control'
    'iwd: for wifi control'
)
conflicts=('dynis-git')
install='dynis.install'
# Generated from the reviewed checkout by scripts/prepare-source.py.
# For a published release, replace the local filename with its immutable asset URL.
source=("$pkgname-$pkgver.tar.gz")
sha256sums=('cec6cd493ce4fad737910f361202625392e34ee5d2598b4bdb10d12a5b0aa5b3')

build() {
  cmake -S "$_srcdir" -B build \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build build
}

package() {
  DESTDIR="$pkgdir" cmake --install build
  chmod +x "$pkgdir/usr/bin/dynis"
  chmod +x "$pkgdir/usr/share/dynis/bin/lyricsmpris"
  chmod +x "$pkgdir/usr/share/dynis/bin/dynis-setup"
}
