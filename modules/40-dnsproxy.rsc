# scripts-ros :: modules/40-dnsproxy.rsc
# Menu entry 4. A caching DNS resolver in its own container, used as the
# routers upstream instead of talking DoH directly.
#
# Recovered from mihomo-proxy-ros: this existed in script.rsc until it was
# removed on 2026-03-25 (commits 0d08d42 and 5fcd611), leaving only a dangling
# $dnsproxy flag behind. The image, the command line and the link network below
# are exactly what that version used.
#
# Link network 192.168.255.8/30 -- .9 is the router, .10 is the container.
# It sits next to the MihomoProxyRoS /30 at 192.168.255.0/30.
#
# The container queries three upstreams in parallel and answers from whichever
# replies first, which is why it is worth having in front of a proxy: a slow or
# blocked resolver stops mattering.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mYesNo
:global mFetch
:global mContState
:global mStateGet

$mHdr "DNSProxy"

:local slot [$mStateGet "slot"]
:if ([:len $slot] = 0) do={
    $mSay "  [ !! ] no storage slot chosen yet, run menu entry 2 first"
} else={

:local rootDir ([$mStateGet "path"] . "Containers/DNSProxy")

# ------------------------------------------------------------------ network
:onerror e in={
    :if ([$mNeed id=[/interface/veth/find where name="DNSProxy"] name="veth DNSProxy"]) do={
        /interface/veth/add name=DNSProxy address=192.168.255.10/30 gateway=192.168.255.9
        $mOk "veth DNSProxy"
    }
    :if ([$mNeed id=[/ip/address/find where address="192.168.255.9/30"] name="address 192.168.255.9/30"]) do={
        /ip/address/add address=192.168.255.9/30 interface=DNSProxy
        $mOk "address 192.168.255.9/30"
    }
    :foreach l in={"InAccept";"Containers"} do={
        :if ([:len [/interface/list/find where name=$l]] = 0) do={
            /interface/list/add name=$l
            $mOk ("interface-list " . $l)
        }
        :if ([$mNeed id=[/interface/list/member/find where list=$l and interface="DNSProxy"] name=("member DNSProxy in " . $l)]) do={
            /interface/list/member/add interface=DNSProxy list=$l
            $mOk ("member DNSProxy in " . $l)
        }
    }
    :if ([$mNeed id=[/ip/dns/forwarders/find where name="DNSProxy"] name="forwarder DNSProxy"]) do={
        /ip/dns/forwarders/add name=DNSProxy dns-servers=192.168.255.10 verify-doh-cert=no
        $mOk "forwarder DNSProxy"
    }
} do={ $mErr "dnsproxy network" $e }

# ---------------------------------------------------------------- container
:if ([:len [/container/find where comment="DNSProxy"]] = 0) do={
    :onerror e in={
        /container/add remote-image="ghcr.io/medium1992/dns-proxy-ros" interface=DNSProxy \
            cmd="--cache --hosts-files=/hosts --ipv6-disabled --upstream https://dns.google/dns-query --upstream https://cloudflare-dns.com/dns-query --upstream https://dns.quad9.net/dns-query --upstream-mode=parallel" \
            root-dir=$rootDir start-on-boot=yes comment="DNSProxy"
        $mOk "container added, pulling image"
    } do={ $mErr "container add" $e }
} else={
    $mOk "container entry already present"
}

# A failed extraction leaves the container in a state that starting will never
# fix; only a repull clears it, so watch for it instead of retrying forever.
:local waited 0
:local done false
:local repulls 0
:while ($done = false and $waited < 600) do={
    :local st [$mContState "DNSProxy"]
    :if ($st = "absent") do={
        $mSay "  [ !! ] container entry disappeared, aborting"
        :set done true
    } else={
        :if ($st = "running") do={
            $mOk ("container running after " . $waited . "s")
            :set done true
        } else={
            :if ([:len [/container/find where comment="DNSProxy" and download/extract failed]] > 0) do={
                :if ($repulls < 3) do={
                    :onerror e in={ /container/repull [find where comment="DNSProxy"] } do={}
                    :set repulls ($repulls + 1)
                    $mSay ("  ... extract failed, repull " . $repulls . " of 3")
                } else={
                    $mSay "  [ !! ] extraction keeps failing, giving up after 3 repulls"
                    :set done true
                }
            } else={
                :if ($st = "stopped") do={
                    :onerror e in={ /container/start [find where comment="DNSProxy" and stopped] } do={}
                }
            }
            :if ($done = false) do={
                :if ($waited % 30 = 0) do={ $mSay ("  ... " . $st . " (" . $waited . "s)") }
                :delay 5
                :set waited ($waited + 5)
            }
        }
    }
}
:if ($done = false) do={
    $mSay "  [ !! ] DNSProxy did not reach running state within 600s"
}

# ------------------------------------------------------- resolver failover
# Pointing /ip dns at the container is only safe with a watchdog: if the
# container stops and the router keeps querying 192.168.255.10, the whole
# network loses DNS.
$mSay ""
:if ([$mYesNo prompt="Use DNSProxy as the router resolver (with automatic fallback)?"]) do={
    :local body [$mFetch "assets/changeDNS.rsc"]
    :if ([:len $body] = 0) do={
        $mErr "changeDNS" "could not fetch assets/changeDNS.rsc"
    } else={
        :onerror e in={
            :if ([:len [/system/script/find where name="changeDNS"]] = 0) do={
                /system/script/add name=changeDNS source=$body comment="sros:dnsproxy"
            } else={
                /system/script/set [find where name="changeDNS"] source=$body
            }
            $mOk "script changeDNS"
            :if ([$mNeed id=[/system/scheduler/find where name="DNSchange"] name="scheduler DNSchange"]) do={
                /system/scheduler/add name=DNSchange interval=10s comment="sros:dnsproxy" \
                    on-event="/system/script/run changeDNS"
                $mOk "scheduler DNSchange every 10s"
            }
            /system/script/run changeDNS
            $mOk ("resolver is now " . [/ip/dns/get servers])
        } do={ $mErr "changeDNS install" $e }
    }
} else={
    $mOk "resolver left as is"
    $mSay "  forward selected domains manually instead:"
    $mSay "  /ip/dns/static/add name=<domain> type=FWD forward-to=DNSProxy match-subdomain=yes"
}

}
