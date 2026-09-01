# scripts-ros :: modules/30-mihomo-remove.rsc
# Removes MihomoProxyRoS and nothing else.
#
# Order matters as much as it does on install, only backwards: the container
# goes before its veth, and the mangle rules go before the routing table they
# mark traffic into, or RouterOS refuses the removal because something still
# references it.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Remove MihomoProxyRoS"

:if ([$mYesNo prompt="Remove the MihomoProxyRoS container and all its routing?"] = false) do={
    $mOk "cancelled"
} else={

:onerror e in={
    :local ids [/container/find where comment="MihomoProxyRoS"]
    :if ([:len $ids] > 0) do={
        :onerror e2 in={ /container/stop $ids } do={}
        :local w 0
        :while ([:len [/container/find where comment="MihomoProxyRoS" and stopped]] = 0 and $w < 30) do={
            :delay 1
            :set w ($w + 1)
        }
        /container/remove $ids
        $mOk "container removed"
    }
} do={ $mErr "container" $e }

:onerror e in={
    /container/envs/remove [find where list="MihomoProxyRoS"]
    /container/mounts/remove [find where list="MihomoProxyRoS"]
    $mOk "envs and mounts removed"
} do={ $mErr "envs and mounts" $e }

:onerror e in={
    :local ids [/ip/firewall/mangle/find where comment="YT_MSS" or comment="Accept_no_mark" or comment="AcceptInWAN&Containers" or comment="RoutingToMihomo1" or comment="RoutingToMihomo2" or comment="MarkConnAddressList" or comment="Discord_RTC" or comment="Discord_WebRTC"]
    :if ([:len $ids] > 0) do={
        /ip/firewall/mangle/remove $ids
        $mOk ([:len $ids] . " mangle rule(s) removed")
    }
} do={ $mErr "mangle" $e }

:onerror e in={
    /ip/route/remove [find where comment="MihomoProxyRoS0" or comment="MihomoProxyRoS1" or routing-table="MihomoProxyRoS"]
    /routing/table/remove [find where comment="MihomoProxyRoS"]
    $mOk "routes and routing table removed"
} do={ $mErr "routes" $e }

:onerror e in={
    /ip/dns/static/remove [find where forward-to="MihomoProxyRoS"]
    /ip/dns/forwarders/remove [find where name="MihomoProxyRoS"]
    $mOk "proxy forwarder and its FWD entries removed"
} do={ $mErr "dns" $e }

# The Apple Private Relay blocks are a separate decision: they are useful with
# any proxy, and someone removing mihomo may well be installing another one.
:if ([$mYesNo prompt="Also un-block Apple Private Relay (mask.icloud.com etc)?"]) do={
    :onerror e in={
        /ip/dns/static/remove [find where name~"icloud.com" or name~"apple.com"]
        $mOk "Apple Private Relay records removed"
    } do={ $mErr "apple records" $e }
} else={
    $mOk "Apple Private Relay stays blocked"
}

:onerror e in={
    /ip/address/remove [find where address="192.168.255.1/30"]
    /interface/list/member/remove [find where interface="MihomoProxyRoS"]
    /interface/veth/remove [find where name="MihomoProxyRoS"]
    $mOk "veth and address removed"
} do={ $mErr "interfaces" $e }

# Tens of thousands of address-list rows take minutes to delete and are inert
# without the mangle rules that read them, so this is asked rather than assumed.
:local rows [:len [/ip/firewall/address-list/find where list="MihomoProxyRoS"]]
:if ($rows > 0) do={
    :if ([$mYesNo prompt=("Also delete " . $rows . " address-list entries? (slow)")]) do={
        :onerror e in={
            /ip/firewall/address-list/remove [find where list="MihomoProxyRoS" or list="YT"]
            $mOk "address-list entries removed"
        } do={ $mErr "address lists" $e }
    } else={
        $mOk ($rows . " address-list entries kept (harmless)")
    }
}

}
