# scripts-ros :: modules/10-base-remove.rsc
# Removes the objects base settings created, and deliberately not the settings.
#
# A forwarder or a route is an object this tool added and can take back. But
# "IPv6 disabled", "NTP enabled" and the hardening switches are not objects,
# they are the state of the router, and there is no previous value to restore:
# re-enabling IPv6 or turning telnet back on would be inventing a configuration
# nobody asked for, on a box that is working. So they are reported, not undone.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Remove base settings"

:if ([$mYesNo prompt="Remove base objects (forwarders, blackholes, NAT workaround)?"] = false) do={
    $mOk "cancelled"
} else={

:onerror e in={
    :local ids [/ip/route/find where comment="BlackHole" and routing-table="main"]
    :if ([:len $ids] > 0) do={
        /ip/route/remove $ids
        $mOk ([:len $ids] . " blackhole route(s) removed")
    }
} do={ $mErr "blackhole routes" $e }

:onerror e in={
    :local ids [/ip/firewall/nat/find where comment~"GitHub_Fastly"]
    :if ([:len $ids] > 0) do={
        /ip/firewall/nat/remove $ids
        $mOk ([:len $ids] . " GitHub Fastly NAT rule(s) removed")
    }
} do={ $mErr "fastly nat" $e }

# Only the forwarders this project defines. A forwarder the operator added by
# hand has a name that is not on this list and survives.
:onerror e in={
    :local names {"Google";"Google-Host";"CloudFlare";"CloudFlare-Host";"Quad9";"Quad9-Host";"XBOX";"XBOX-DOH";"Yandex";"Google8";"NSDI";"Fallback"}
    :local n 0
    :foreach f in=$names do={
        :local ids [/ip/dns/forwarders/find where name=$f]
        :if ([:len $ids] > 0) do={
            /ip/dns/forwarders/remove $ids
            :set n ($n + 1)
        }
    }
    $mOk ($n . " DNS forwarder(s) removed")
} do={ $mErr "forwarders" $e }

# The bootstrap A records only, matched by the comments this tool writes.
:onerror e in={
    :local ids [/ip/dns/static/find where comment~"^DNS " or comment="XBOX DNS"]
    :if ([:len $ids] > 0) do={
        /ip/dns/static/remove $ids
        $mOk ([:len $ids] . " bootstrap DNS record(s) removed")
    }
    :local ntp [/ip/dns/static/find where name="pool.ntp.org"]
    :if ([:len $ntp] > 0) do={
        /ip/dns/static/remove $ntp
        $mOk "pool.ntp.org forward removed"
    }
} do={ $mErr "static records" $e }

# The fasttrack rule itself belongs to the router, only our restriction is
# ours to lift.
:onerror e in={
    :local ft [/ip/firewall/filter/find where action=fasttrack-connection and connection-mark="no-mark"]
    :if ([:len $ft] > 0) do={
        /ip/firewall/filter/set $ft connection-mark=""
        $mOk "fasttrack restriction lifted"
    }
} do={ $mErr "fasttrack" $e }

$mSay ""
$mSay "  left untouched on purpose:"
$mSay "   - IPv6 stays disabled, NTP stays enabled, hardening stays applied"
$mSay "   - interface lists WAN and LAN, they are router configuration"
$mSay "   - /ip dns resolver settings (cache size, DoH, allow-remote-requests)"
$mSay "  revert those by hand if you actually want them back."

}
