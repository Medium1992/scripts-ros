# scripts-ros :: modules/13-ipv6.rsc
# IPv6 off. The proxy path is v4 only; a live v6 route silently bypasses every
# mangle rule this project installs, which looks like "the proxy stopped
# working for some sites" and is miserable to debug.

:global mHdr
:global mOk
:global mErr

$mHdr "IPv6"

:onerror e in={
    /ipv6/nd/set [find where default=yes] advertise-dns=yes disabled=yes
    $mOk "router advertisements off"
} do={ $mErr "ipv6 nd" $e }

:onerror e in={
    /ipv6/settings/set accept-redirects=no accept-router-advertisements=no \
        accept-router-advertisements-on=none allow-fast-path=no \
        disable-ipv6=yes disable-link-local-address=yes forward=no
    $mOk "ipv6 disabled"
} do={ $mErr "ipv6 settings" $e }
