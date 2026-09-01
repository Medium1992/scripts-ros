# scripts-ros :: modules/31-mihomo-net.rsc
# The plumbing between RouterOS and the container: a veth pair on a /30, a
# dedicated routing table, and the routes that send marked traffic into it.
#
# 192.168.255.0/30 is the link network. .1 is the router, .2 is the container,
# and every reference to .2 elsewhere in the project means "the proxy".

:global mHdr
:global mOk
:global mNeed
:global mErr
:global mSay
:global mStateGet

$mHdr "MihomoProxyRoS network"

# Prerequisite. These lists drive include= and in-interface-list= below, and
# RouterOS rejects a rule referring to a list that does not exist with a
# message that says nothing about what is missing. Fail clearly instead.
#
# Container-only mode needs WAN (InAccept includes it, which is what stops the
# proxy from looping its own egress back into itself) but not LAN, because
# nothing from the LAN is being redirected.
:local mode [$mStateGet "mihomo_mode"]
:if ([:len $mode] = 0) do={ :set mode "full" }

:local needed {"WAN"}
:if ($mode = "full") do={ :set needed ($needed, "LAN") }
:foreach l in=$needed do={
    :if ([:len [/interface/list/find where name=$l]] = 0) do={
        $mSay ("  [ !! ] interface list " . $l . " does not exist.")
        $mSay "         Run row 10 (Base settings) first."
        :error ("missing interface list " . $l)
    }
}

:onerror e in={
    :if ([$mNeed id=[/interface/veth/find where name="MihomoProxyRoS"] name="veth MihomoProxyRoS"]) do={
        /interface/veth/add name=MihomoProxyRoS address=192.168.255.2/30 gateway=192.168.255.1
        $mOk "veth MihomoProxyRoS"
    }
    :if ([$mNeed id=[/ip/address/find where address="192.168.255.1/30"] name="address 192.168.255.1/30"]) do={
        /ip/address/add address=192.168.255.1/30 interface=MihomoProxyRoS
        $mOk "address 192.168.255.1/30"
    }
} do={ $mErr "veth" $e }

# InAccept marks traffic that must never be re-routed into the proxy: WAN
# return traffic and the container own egress. Without it the proxy loops.
:onerror e in={
    :if ([$mNeed id=[/interface/list/find where name="InAccept"] name="interface-list InAccept"]) do={
        /interface/list/add name=InAccept include=WAN
        $mOk "interface-list InAccept"
    }
    :if ([$mNeed id=[/interface/list/find where name="Containers"] name="interface-list Containers"]) do={
        /interface/list/add name=Containers
        $mOk "interface-list Containers"
    }
    :foreach l in={"InAccept";"Containers"} do={
        :if ([$mNeed id=[/interface/list/member/find where list=$l and interface="MihomoProxyRoS"] name=("member MihomoProxyRoS in " . $l)]) do={
            /interface/list/member/add interface=MihomoProxyRoS list=$l
            $mOk ("member MihomoProxyRoS in " . $l)
        }
    }
} do={ $mErr "interface lists" $e }

# A forwarder pointing at the container lets /ip dns static FWD rules send
# selected domains through the proxy resolver and its fake-ip pool.
:onerror e in={
    :if ([$mNeed id=[/ip/dns/forwarders/find where name="MihomoProxyRoS"] name="forwarder MihomoProxyRoS"]) do={
        /ip/dns/forwarders/add name=MihomoProxyRoS dns-servers=192.168.255.2 verify-doh-cert=no
        $mOk "forwarder MihomoProxyRoS"
    }
} do={ $mErr "dns forwarder" $e }

# The routing table and its routes exist to carry redirected traffic. In
# container-only mode nothing is redirected, so creating them would leave a
# table that nothing marks into -- confusing to find later, and one more thing
# to explain when it does not work.
:if ($mode != "full") do={
    $mSay ""
    $mSay "  container-only mode: routing table and policy routes skipped"
} else={

:onerror e in={
    :if ([$mNeed id=[/routing/table/find where comment="MihomoProxyRoS"] name="routing-table MihomoProxyRoS"]) do={
        /routing/table/add name=MihomoProxyRoS fib comment="MihomoProxyRoS"
        $mOk "routing-table MihomoProxyRoS"
    }
} do={ $mErr "routing table" $e }

:onerror e in={
    :if ([$mNeed id=[/ip/route/find where comment="MihomoProxyRoS0"] name="default route into proxy table"]) do={
        /ip/route/add dst-address=0.0.0.0/0 gateway=192.168.255.2 routing-table=MihomoProxyRoS comment="MihomoProxyRoS0"
        $mOk "default route into proxy table"
    }
    # The same private blackholes as the main table: a marked packet destined
    # for a LAN address must be dropped, not tunnelled.
    :foreach p in={"10.0.0.0/8";"172.16.0.0/12";"192.168.0.0/16"} do={
        :if ([$mNeed id=[/ip/route/find where dst-address=$p and routing-table="MihomoProxyRoS"] name=("blackhole " . $p . " in proxy table")]) do={
            /ip/route/add blackhole comment=BlackHole distance=254 dst-address=$p gateway="" routing-table=MihomoProxyRoS
            $mOk ("blackhole " . $p . " in proxy table")
        }
    }
    # fake-ip answers come back in 198.18.0.0/15 and must reach the container
    # from the main table, otherwise clients get an address that routes nowhere.
    :if ([$mNeed id=[/ip/route/find where comment="MihomoProxyRoS1"] name="route 198.18.0.0/15 (fake-ip)"]) do={
        /ip/route/add dst-address=198.18.0.0/15 gateway=192.168.255.2 comment="MihomoProxyRoS1"
        $mOk "route 198.18.0.0/15 (fake-ip)"
    }
} do={ $mErr "routes" $e }

}
