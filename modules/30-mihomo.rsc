# scripts-ros :: modules/30-mihomo.rsc
# Menu entry 30. Asks what kind of install this is, then orchestrates it.
#
# Two very different things were bundled under one name before:
#
#   full        the container PLUS the traffic redirection -- mangle marks,
#               a dedicated routing table, fake-ip routes, address-lists and
#               static DNS. Everything from the LAN goes through the proxy by
#               policy. This is what script21.rsc always did, with no choice.
#   container   the container and its link network only. Nothing on the router
#               is redirected. You decide what reaches it, by pointing DNS FWD
#               rules or your own firewall rules at it.
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
:global mStateSet

$mHdr "MihomoProxyRoS"

:local mode [$mStateGet "mihomo_mode"]
$mSay ""
:if ([:len $mode] > 0) do={
    $mSay ("  this router is currently set up as: " . $mode)
}
$mSay "   1) full      container + traffic redirection for the whole LAN"
$mSay "   2) container container and link network only, you route to it yourself"
$mSay "   3) back"
$mSay "  choose:"
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

# 32-mihomo-mangle is the redirection. It is the only difference between the
# two modes, and it is the whole difference.
:local steps {"modules/31-mihomo-net.rsc"}
:if ($mode = "full") do={ :set steps ($steps, "modules/32-mihomo-mangle.rsc") }
:set steps ($steps, "modules/33-mihomo-env.rsc")
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
$mSay "  web panel: http://192.168.255.2:9090/ui/"
$mSay "  WG/AWG configs go to /awg_conf/ on the router"
:if ($mode = "container") do={
    $mSay ""
    $mSay "  nothing is redirected. Send traffic to the proxy yourself, e.g."
    $mSay "  /ip/dns/static/add name=<domain> type=FWD forward-to=MihomoProxyRoS match-subdomain=yes"
    $mSay "  or mark connections into a routing table of your own."
    $mSay "  switching to full mode later is just row 30 again."
}

}
}
