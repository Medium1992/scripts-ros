# scripts-ros :: modules/13-ipv6.rsc
# IPv6 off. The proxy path is v4 only; a live v6 route silently bypasses every
# mangle rule this project installs, which looks like "the proxy stopped
# working for some sites" and is miserable to debug.

:global mHdr
:global mOk
:global mErr
:global mSkip

$mHdr "IPv6"

:if ([/ipv6/settings/get disable-ipv6] = true) do={
    $mSkip "ipv6 already disabled"
} else={
    :onerror e in={
        /ipv6/nd/set [find where default=yes] advertise-dns=yes disabled=yes
        /ipv6/settings/set accept-redirects=no accept-router-advertisements=no             accept-router-advertisements-on=none allow-fast-path=no             disable-ipv6=yes disable-link-local-address=yes forward=no
        $mOk "ipv6 disabled, router advertisements off"
    } do={ $mErr "ipv6" $e }
}
