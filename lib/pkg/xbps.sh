# Requires: xbps-install, xbps-query
pkg_bootstrap() { XBPS_ARCH=x86_64 xbps-install -Sy -r "${VFF_TARGET}" base-system; }
pkg_install()  { xbps-install -Sy -r "${VFF_TARGET}" "$@"; }
pkg_chroot()   { chroot "${VFF_TARGET}" "$@"; }
pkg_query()    { xbps-query -r "${VFF_TARGET}" "$1" &>/dev/null; }
pkg_repo_setup() { xbps-install -S; }
pkg_lock_clean() { rm -f "${VFF_TARGET}/var/lib/xbps/db.lck"; }

pkg_install_local() {
    local artifact="${1}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    xbps-install -y -r "${VFF_TARGET}" "/root/${artifact##*/}" || die "xbps local install failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}