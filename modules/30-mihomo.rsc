# scripts-ros :: modules/30-mihomo.rsc
# Menu entry 3. Orchestration only.
#
# Order: network plumbing, then policy, then environment, then the link, and
# only then the container -- so that when the image finally starts, everything
# it expects to find on the router is already there and it does not have to be
# restarted afterwards.

:global mHdr
:global mSay
:global mRun
:global mStateGet

$mHdr "MihomoProxyRoS"

:if ([:len [$mStateGet "slot"]] = 0) do={
    $mSay "  no storage slot chosen yet, running menu entry 2 first"
    $mRun "modules/20-storage.rsc"
}

:local steps {
    "modules/31-mihomo-net.rsc";
    "modules/32-mihomo-mangle.rsc";
    "modules/33-mihomo-env.rsc";
    "modules/60-links.rsc";
    "modules/34-mihomo-run.rsc"
}

:local failed 0
:foreach s in=$steps do={
    :if ([$mRun $s] = false) do={ :set failed ($failed + 1) }
}

$mSay ""
:if ($failed = 0) do={
    $mSay "  MihomoProxyRoS complete"
    $mSay "  web panel: http://192.168.255.2:9090/ui/"
    $mSay "  WG/AWG configs go to /awg_conf/ on the router"
} else={
    $mSay ("  MihomoProxyRoS finished with " . $failed . " failed module(s), see above")
}
