# scripts-ros :: modules/41-adguard-remove.rsc
# Removes AdGuard Home.
#
# The two mounted directories hold the filter configuration and the query log.
# They survive by default: they are the part that took effort to set up, and
# they cost nothing to keep.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Remove AdGuard Home"

:if ([$mYesNo prompt="Remove the AdGuard Home container?"] = false) do={
    $mOk "cancelled"
} else={

:onerror e in={
    :if ([/ip/dns/get servers] = "192.168.255.14") do={
        /ip/dns/set servers="8.8.8.8" use-doh-server="https://dns.google/dns-query" verify-doh-cert=yes
        /ip/dns/cache/flush
        $mOk "resolver restored to DoH Google"
    }
} do={ $mErr "resolver" $e }

:onerror e in={
    :local ids [/container/find where comment="AdGuardHome"]
    :if ([:len $ids] > 0) do={
        :onerror e2 in={ /container/stop $ids } do={}
        :local w 0
        :while ([:len [/container/find where comment="AdGuardHome" and stopped]] = 0 and $w < 30) do={
            :delay 1
            :set w ($w + 1)
        }
        /container/remove $ids
        $mOk "container removed"
    }
} do={ $mErr "container" $e }

:onerror e in={
    /container/mounts/remove [find where list="AdGuardHome"]
    /ip/dns/static/remove [find where forward-to="AdGuardHome"]
    /ip/dns/forwarders/remove [find where name="AdGuardHome"]
    /ip/address/remove [find where address="192.168.255.13/30"]
    /interface/list/member/remove [find where interface="AdGuardHome"]
    /interface/veth/remove [find where name="AdGuardHome"]
    $mOk "mounts, forwarder, veth and address removed"
} do={ $mErr "network" $e }

:if ([$mYesNo prompt="Also delete the AdGuard config and query log directories?"]) do={
    :onerror e in={
        /file/remove [find where name~"^adguard_work" or name~"^adguard_conf"]
        $mOk "adguard directories deleted"
    } do={ $mErr "directories" $e }
} else={
    $mSay "  /adguard_conf/ and /adguard_work/ kept, a reinstall picks them up"
}

}
