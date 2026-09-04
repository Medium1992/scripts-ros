# scripts-ros :: modules/30-mihomo.rsc
# Menu entry 30. Asks what kind of install this is, then orchestrates it.
#
# Two very different things were bundled under one name before:
#
#   container   a working, reachable proxy: link network, its own routing
#               table, the default route into it, the private blackholes and
#               the fake-ip route. Nothing is redirected into it. You decide
#               what arrives, with a DNS FWD rule or your own marking.
#   full        all of that plus the policy that fills it: mangle marks,
#               the group and geosite environment, static DNS and the firewall
#               address-lists. Everything from the LAN goes through the proxy.
#               This is what script21.rsc always did, with no choice.
#
# The line between them is what decides which traffic arrives, not what makes
# the container usable. A routing table nobody can reach is not a lighter
# install, it is a broken one.
#
# The second case is not exotic. Someone who already has their own mangle
# rules, or who wants the proxy for a handful of domains, or who is just trying
# the image out, should not have to unpick a policy they never asked for.
#
# Order in full mode: plumbing, then policy, then environment, then the link,
# then the container -- so that when the image starts, everything it expects on
# the router is already there and it needs no second restart.

:global mHdr
:global mSay
:global mOk
:global mRun
:global mAsk
:global mStateGet
:global mNetAddr
:global mStateSet

$mHdr "MihomoProxyRoS"

:local mode [$mStateGet "mihomo_mode"]
$mSay ""
:if ([:len $mode] > 0) do={
    $mSay ("  this router is currently set up as: " . $mode)
}
$mSay "   1) full      container + redirection policy for the whole LAN"
$mSay "   2) container working proxy with its routes, nothing redirected yet"
$mSay "   3) back"
$mSay "  choose, or Enter to go back:"
:local pick [$mAsk default=""]

:if ($pick = "3" or [:len $pick] = 0) do={
    $mOk "nothing changed"
} else={
:if ($pick != "1" and $pick != "2") do={
    $mSay "  not a valid choice"
} else={

:if ($pick = "1") do={ :set mode "full" } else={ :set mode "container" }
$mStateSet key="mihomo_mode" value=$mode
$mOk ("install mode: " . $mode)

:if ([:len [$mStateGet "slot"]] = 0) do={
    $mSay "  no storage slot chosen yet, running row 20 first"
    $mRun "modules/20-storage.rsc"
}

# Policy is the difference: the marking rules and the group environment that
# tells mihomo what to do with what. Everything else is the container itself.
:local steps {"modules/31-mihomo-net.rsc"}
:if ($mode = "full") do={
    :set steps ($steps, "modules/32-mihomo-mangle.rsc")
    :set steps ($steps, "modules/33-mihomo-env.rsc")
}
:set steps ($steps, "modules/60-links.rsc")
:set steps ($steps, "modules/34-mihomo-run.rsc")

:local failed 0
:foreach s in=$steps do={
    :if ([$mRun $s] = false) do={ :set failed ($failed + 1) }
}

$mSay ""
:if ($failed = 0) do={
    $mSay ("  MihomoProxyRoS complete (" . $mode . ")")
} else={
    $mSay ("  MihomoProxyRoS finished with " . $failed . " failed module(s), see above")
}
:local mhIP [$mNetAddr "MihomoProxyRoS"]
:if ([:len $mhIP] > 0) do={
    $mSay ("  web panel: http://" . $mhIP . ":9090/ui/")
} else={
    $mSay "  web panel: on the container address, port 9090, path /ui/"
}
$mSay "  WG/AWG configs go to /awg_conf/ on the router"
:if ($mode = "container") do={
    $mSay ""
    $mSay "  the proxy is up and routable, but nothing is sent to it yet, and"
    $mSay "  no group policy was applied -- mihomo runs on its own defaults."
    $mSay "  send it traffic with, for example:"
    $mSay "  /ip/dns/static/add name=<domain> type=FWD forward-to=MihomoProxyRoS match-subdomain=yes"
    $mSay "  or mark connections into the MihomoProxyRoS routing table yourself."
    $mSay "  row 30 again, choosing full, adds the policy without redoing the rest."
}

}
}
