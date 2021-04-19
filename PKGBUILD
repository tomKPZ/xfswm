pkgname=xfswm
pkgver=0.0.1
pkgrel=1
pkgdesc="An X11 window manager that keeps a single window fullscreen"
url="https://github.com/tomKPZ/xfswm"
arch=("x86_64")
license=("MIT")
depends=("glibc" "libxcb")
makedepends=("cmake" "git")

build() {
    cmake . -DCMAKE_INSTALL_PREFIX=/usr
    make
}

package() {
    make DESTDIR="$pkgdir" install
}
