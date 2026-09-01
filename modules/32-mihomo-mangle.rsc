# scripts-ros :: modules/32-mihomo-mangle.rsc
# Connection marking, routing marks and the DNS entries that decide what goes
# through the proxy.
#
# Rule order is load-bearing. The accept rules must precede the marking rules,
# or established traffic gets re-marked mid-connection. On a clean router the
# insertion order below is the final order; when repairing a partly configured
# box, check /ip/firewall/mangle/print afterwards.

:global mHdr
:global mOk
:global mNeed
:global mErr
:global mSay

$mHdr "MihomoProxyRoS mangle and DNS"

# Prerequisite. WAN and LAN drive include= and in-interface-list= below, and
# RouterOS rejects a rule referring to a list that does not exist with a
# message that says nothing about what is actually missing. Fail clearly.
:foreach l in={"WAN";"LAN"} do={
    :if ([:len [/interface/list/find where name=$l]] = 0) do={
        $mSay ("  [ !! ] interface list " . $l . " does not exist.")
        $mSay "         Run menu entry 1 (Base settings) first."
        :error ("missing interface list " . $l)
    }
}

:onerror e in={
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="YT_MSS"] name="mangle YT_MSS"]) do={
        /ip/firewall/mangle/add action=change-mss chain=forward dst-address-list=YT in-interface=MihomoProxyRoS new-mss=88 protocol=tcp tcp-flags=syn connection-state=new comment="YT_MSS"
        $mOk "mangle YT_MSS"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="Accept_no_mark"] name="mangle Accept_no_mark"]) do={
        /ip/firewall/mangle/add action=accept chain=prerouting connection-mark=no-mark connection-state=established comment="Accept_no_mark"
        $mOk "mangle Accept_no_mark"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="AcceptInWAN&Containers"] name="mangle AcceptInWAN-Containers"]) do={
        /ip/firewall/mangle/add action=accept chain=prerouting in-interface-list=InAccept comment="AcceptInWAN&Containers"
        $mOk "mangle AcceptInWAN-Containers"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="RoutingToMihomo2"] name="mangle RoutingToMihomo2"]) do={
        /ip/firewall/mangle/add action=mark-routing chain=prerouting in-interface-list=LAN connection-mark=MihomoProxyRoS new-routing-mark=MihomoProxyRoS passthrough=no comment="RoutingToMihomo2"
        $mOk "mangle RoutingToMihomo2"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="MarkConnAddressList"] name="mangle MarkConnAddressList"]) do={
        /ip/firewall/mangle/add action=mark-connection chain=prerouting in-interface-list=LAN connection-mark=no-mark connection-state=new dst-address-list=MihomoProxyRoS new-connection-mark=MihomoProxyRoS comment="MarkConnAddressList"
        $mOk "mangle MarkConnAddressList"
    }
} do={ $mErr "mangle base" $e }

# Discord voice picks random UDP ports, so it is matched by payload signature
# and connection size rather than by destination.
:onerror e in={
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="Discord_RTC"] name="mangle Discord_RTC"]) do={
        /ip/firewall/mangle/add action=mark-connection chain=prerouting connection-bytes=102 connection-mark=no-mark connection-state=new content="\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00" dst-address-type=!local in-interface-list=LAN new-connection-mark=MihomoProxyRoS dst-port=19294-19344,50000-50100 protocol=udp comment="Discord_RTC"
        $mOk "mangle Discord_RTC"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="Discord_WebRTC"] name="mangle Discord_WebRTC"]) do={
        /ip/firewall/mangle/add action=mark-connection chain=prerouting connection-bytes=128 connection-mark=no-mark connection-state=new content="\12\A4\42" dst-address-type=!local in-interface-list=LAN new-connection-mark=MihomoProxyRoS dst-port=19294-19344,50000-50100 protocol=udp comment="Discord_WebRTC"
        $mOk "mangle Discord_WebRTC"
    }
    :if ([$mNeed id=[/ip/firewall/mangle/find where comment="RoutingToMihomo1"] name="mangle RoutingToMihomo1"]) do={
        /ip/firewall/mangle/add action=mark-routing chain=prerouting in-interface-list=LAN connection-mark=MihomoProxyRoS new-routing-mark=MihomoProxyRoS passthrough=no comment="RoutingToMihomo1"
        $mOk "mangle RoutingToMihomo1"
    }
} do={ $mErr "mangle discord" $e }

# ------------------------------------------------------------ address lists
:onerror e in={
    :foreach a in={"1.1.1.1";"9.9.9.9";"149.112.112.112";"104.16.248.249";"104.16.249.249";"8.8.8.8";"8.8.4.4"} do={
        :if ([$mNeed id=[/ip/firewall/address-list/find where list="DNS" and address=$a] name=("address-list DNS " . $a)]) do={
            /ip/firewall/address-list/add address=$a list=DNS
            $mOk ("address-list DNS " . $a)
        }
    }
    :if ([$mNeed id=[/ip/firewall/address-list/find where list="YT"] name="address-list YT"]) do={
        /ip/firewall/address-list/add list=YT comment=YT_MSS address=www.youtube.com
        $mOk "address-list YT"
    }
    :foreach a in={"www.youtube.com";"ntc.party"} do={
        :if ([$mNeed id=[/ip/firewall/address-list/find where list="MihomoProxyRoS" and address=$a] name=("address-list MihomoProxyRoS " . $a)]) do={
            /ip/firewall/address-list/add list=MihomoProxyRoS address=$a
            $mOk ("address-list MihomoProxyRoS " . $a)
        }
    }
} do={ $mErr "address lists" $e }

# ------------------------------------------------------------- static DNS
# Apple Private Relay is answered with NXDOMAIN: left alone it tunnels client
# traffic past the proxy entirely and the routing rules never see it.
:onerror e in={
    :foreach n in={"mask.icloud.com";"mask-h2.icloud.com";"doh.dns.apple.com";"dns.apple.com"} do={
        :if ([$mNeed id=[/ip/dns/static/find where name=$n] name=("NXDOMAIN " . $n)]) do={
            /ip/dns/static/add name=$n type=NXDOMAIN
            $mOk ("NXDOMAIN " . $n)
        }
    }
    :if ([$mNeed id=[/ip/dns/static/find where name="ntc.party"] name="cname ntc.party"]) do={
        /ip/dns/static/add comment=NTCParty name=ntc.party type=CNAME cname=box.ntc.party
        $mOk "cname ntc.party"
    }
    :foreach n in={"usher.ttvnw.net";"gql.twitch.tv"} do={
        :if ([$mNeed id=[/ip/dns/static/find where name=$n] name=("FWD " . $n . " to proxy")]) do={
            /ip/dns/static/add comment=twitch forward-to=MihomoProxyRoS match-subdomain=yes name=$n type=FWD
            $mOk ("FWD " . $n . " to proxy")
        }
    }
} do={ $mErr "static dns" $e }
