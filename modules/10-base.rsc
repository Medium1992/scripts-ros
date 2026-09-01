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
    $mSay "  base settings complete"
} else={
    $mSay ("  base settings finished with " . $failed . " failed module(s), see above")
}
