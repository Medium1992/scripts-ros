# scripts-ros :: modules/90-uninstall.rsc
# Menu entry x. Removes what this installer created, in dependency order.
#
# The inventory is explicit rather than a comment-prefix sweep, because the
# object names here are shared with the upstream mihomo project: a blind
# "delete everything tagged sros" would either miss objects created by the
# older script21.rsc, or delete a rule the operator wrote themselves.
#
# Base settings (DNS, NTP, IPv6, hardening) are deliberately NOT removed. They
# are ordinary router configuration, not artifacts of this tool, and reverting
# them would knock the router off the network.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Uninstall"

$mSay "  this removes: containers, veth, proxy routes and table, mangle rules,"
$mSay "  container envs and mounts, managed scripts and schedulers, state."
$mSay "  it keeps: DNS forwarders, NTP, IPv6 settings, hardening, interface lists."
$mSay ""

:if ([$mYesNo prompt="Proceed with uninstall?"] = false) do={
    $mOk "cancelled"
} else={

# Containers first: their veth and root-dir cannot go while they are running.
:foreach c in={"MihomoProxyRoS";"DNSProxy"} do={
    :onerror e in={
        :local ids [/container/find where comment=$c]
        :if ([:len $ids] > 0) do={
            :onerror e2 in={ /container/stop $ids } do={}
            :local waited 0
            :while ([:len [/container/find where comment=$c and stopped]] = 0 and $waited < 30) do={
                :delay 1
                :set waited ($waited + 1)
            }
            /container/remove $ids
            $mOk ("container " . $c . " removed")
        }
    } do={ $mErr ("container " . $c) $e }
}

:onerror e in={
    /container/envs/remove [find where list="MihomoProxyRoS" or list="DNSProxy"]
    /container/mounts/remove [find where list="MihomoProxyRoS" or list="DNSProxy"]
    $mOk "container envs and mounts removed"
} do={ $mErr "envs and mounts" $e }

:onerror e in={
    /ip/firewall/mangle/remove [find where comment="YT_MSS" or comment="Accept_no_mark" or comment="AcceptInWAN&Containers" or comment="RoutingToMihomo1" or comment="RoutingToMihomo2" or comment="MarkConnAddressList" or comment="Discord_RTC" or comment="Discord_WebRTC"]
    $mOk "mangle rules removed"
} do={ $mErr "mangle" $e }

:onerror e in={
    /ip/route/remove [find where comment="MihomoProxyRoS0" or comment="MihomoProxyRoS1" or routing-table="MihomoProxyRoS"]
    /routing/table/remove [find where comment="MihomoProxyRoS"]
    $mOk "proxy routes and routing table removed"
} do={ $mErr "routes" $e }

# The resolver watchdog goes before the container, or it will helpfully
# switch DNS back the moment the container stops and leave the router
# pointing at an address that no longer answers.
:onerror e in={
    :if ([:len [/system/script/find where name="changeDNS"]] > 0) do={
        /system/scheduler/remove [find where name="DNSchange"]
        /system/script/remove [find where name="changeDNS"]
        :if ([/ip/dns/get servers] = "192.168.255.10") do={
            /ip/dns/set servers="8.8.8.8" use-doh-server="https://dns.google/dns-query" verify-doh-cert=yes
            /ip/dns/cache/flush
            $mOk "resolver restored to DoH"
        }
        $mOk "changeDNS watchdog removed"
    }
} do={ $mErr "changeDNS" $e }

:onerror e in={
    /ip/dns/forwarders/remove [find where name="MihomoProxyRoS" or name="DNSProxy"]
    /ip/dns/static/remove [find where forward-to="MihomoProxyRoS" or forward-to="DNSProxy"]
    $mOk "proxy DNS forwarders and their FWD entries removed"
} do={ $mErr "dns" $e }

:onerror e in={
    /ip/address/remove [find where address="192.168.255.1/30" or address="192.168.255.9/30"]
    /interface/list/member/remove [find where interface="MihomoProxyRoS" or interface="DNSProxy"]
    /interface/veth/remove [find where name="MihomoProxyRoS" or name="DNSProxy"]
    $mOk "veth interfaces and addresses removed"
} do={ $mErr "interfaces" $e }

:onerror e in={
    /system/scheduler/remove [find where name="update_FWD" or name="route_UP" or name="MihomoProxyRoS_repull" or name="DNSchange"]
    $mOk "schedulers removed"
} do={ $mErr "schedulers" $e }

# The operator lists are offered separately: they may represent hours of
# tuning, and they are useless to no one if kept.
:if ([$mYesNo prompt="Also delete your resource lists (FWD_update_list etc)?"]) do={
    :onerror e in={
        /system/script/remove [find where name~"_list\$"]
        $mOk "operator lists removed"
    } do={ $mErr "operator lists" $e }
} else={
    $mOk "operator lists kept"
}

:onerror e in={
    /system/script/remove [find where name="FWD_update" or name="FWD_update_RU" or name="IP_MihomoProxyRoS" or name="route_UP" or name="MihomoProxyRoS_repull"]
    /system/script/remove [find where name~"_bak\$" and comment="sros:backup"]
    /system/script/remove [find where name="sros_state"]
    $mOk "managed scripts and state removed"
} do={ $mErr "scripts" $e }

# Populated entries are left in place on purpose: removing tens of thousands of
# address-list rows takes minutes and they are harmless without the mangle
# rules that referenced them. Say so rather than leaving it a mystery.
:local leftovers [:len [/ip/firewall/address-list/find where list="MihomoProxyRoS" or list="DNS" or list="YT"]]
:if ($leftovers > 0) do={
    $mSay ""
    $mSay ("  note: " . $leftovers . " address-list entries left in place (harmless).")
    $mSay "  to clear them: /ip/firewall/address-list/remove [find where list=\"MihomoProxyRoS\"]"
}

$mSay ""
$mOk "uninstall complete"

}
