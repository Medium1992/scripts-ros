# scripts-ros :: modules/40-dnsproxy-remove.rsc
# Removes DNSProxy.
#
# The watchdog goes first and the resolver is restored before the container is
# touched. Reverse that order and changeDNS fires during the removal, points
# /ip dns at an address that is about to stop answering, and the network loses
# DNS at exactly the moment you are busy.

:global mHdr
:global mOk
:global mErr
:global mYesNo

$mHdr "Remove DNSProxy"

:if ([$mYesNo prompt="Remove the DNSProxy container and its resolver watchdog?"] = false) do={
    $mOk "cancelled"
} else={

:onerror e in={
    :if ([:len [/system/scheduler/find where name="DNSchange"]] > 0) do={
        /system/scheduler/remove [find where name="DNSchange"]
        $mOk "scheduler DNSchange removed"
    }
    :if ([:len [/system/script/find where name="changeDNS"]] > 0) do={
        /system/script/remove [find where name="changeDNS"]
        $mOk "script changeDNS removed"
    }
} do={ $mErr "watchdog" $e }

:onerror e in={
    :if ([/ip/dns/get servers] = "192.168.255.10") do={
        /ip/dns/set servers="8.8.8.8" use-doh-server="https://dns.google/dns-query" verify-doh-cert=yes
        /ip/dns/cache/flush
        $mOk "resolver restored to DoH Google"
    }
} do={ $mErr "resolver" $e }

:onerror e in={
    :local ids [/container/find where comment="DNSProxy"]
    :if ([:len $ids] > 0) do={
        :onerror e2 in={ /container/stop $ids } do={}
        :local w 0
        :while ([:len [/container/find where comment="DNSProxy" and stopped]] = 0 and $w < 30) do={
            :delay 1
            :set w ($w + 1)
        }
        /container/remove $ids
        $mOk "container removed"
    }
} do={ $mErr "container" $e }

:onerror e in={
    /ip/dns/static/remove [find where forward-to="DNSProxy"]
    /ip/dns/forwarders/remove [find where name="DNSProxy"]
    /ip/address/remove [find where address="192.168.255.9/30"]
    /interface/list/member/remove [find where interface="DNSProxy"]
    /interface/veth/remove [find where name="DNSProxy"]
    $mOk "forwarder, veth and address removed"
} do={ $mErr "network" $e }

}
