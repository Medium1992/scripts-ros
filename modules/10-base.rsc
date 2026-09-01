# scripts-ros :: modules/10-base.rsc
# Menu entry 1. Pure orchestration -- it owns no configuration of its own, it
# just runs the base modules in dependency order and reports what failed.
#
# Order matters: DNS before NTP (the pool hostnames must resolve), NTP before
# anything fetched over https (certificates need a correct clock).

:global mHdr
:global mSay
:global mRun

$mHdr "Base settings"

$mSay ""
$mSay "  This step sets up the router itself, before any container exists:"
$mSay "    DNS      resolver, forwarders and bootstrap records"
$mSay "    NTP      clock, which every TLS handshake depends on"
$mSay "    IPv6     turned off, so nothing bypasses the proxy path later"
$mSay "    network  WAN and LAN lists, blackholes, the GitHub workaround"
$mSay "    certs    the root certificates RouterOS is missing (optional)"
$mSay "    harden   local access services (optional)"
$mSay ""
$mSay "  You will be asked four questions along the way."

:local steps {
    "modules/11-dns.rsc";
    "modules/12-ntp.rsc";
    "modules/13-ipv6.rsc";
    "modules/15-netbase.rsc";
    "modules/16-cacert.rsc";
    "modules/14-hardening.rsc"
}

:local failed 0
:foreach s in=$steps do={
    :if ([$mRun $s] = false) do={ :set failed ($failed + 1) }
}

$mSay ""
:if ($failed = 0) do={
    $mSay "  --- base settings complete ---"
} else={
    $mSay ("  --- base settings finished with " . $failed . " failed step(s), see above ---")
}
:global mFallbackDesc
$mSay ("  resolver     : " . [$mFallbackDesc])
$mSay ("  forwarders   : " . [:len [/ip/dns/forwarders/find]])
$mSay ("  WAN / LAN    : " . [:len [/interface/list/member/find where list="WAN"]] . " / " . [:len [/interface/list/member/find where list="LAN"]] . " member(s)")
$mSay ("  root certs   : " . [:len [/certificate/find where name~"^cacert.pem" or name~"_CA\$"]] . " imported")
$mSay ""
$mSay "  next: row 2 tests the DoH forwarders, row 3 picks container storage."
