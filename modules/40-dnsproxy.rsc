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
:global mRepull
:global mStateSet
:global mRun

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

$mRepull name="DNSProxy" image="ghcr.io/medium1992/dns-proxy-ros" iface="DNSProxy"     envs="DNSProxy" mounts=""     cmd="--cache --hosts-files=/hosts --ipv6-disabled --upstream https://dns.google/dns-query --upstream https://cloudflare-dns.com/dns-query --upstream https://dns.quad9.net/dns-query --upstream-mode=parallel"

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

$mSay ""
$mSay "  DNSProxy has no web interface: it is configured entirely by its"
$mSay "  command line, which this module set to three parallel DoH upstreams."
$mSay "  To change them:"
$mSay "    /container/set [find where comment=DNSProxy] cmd=..."
$mSay "  then restart the container. Options: github.com/AdguardTeam/dnsproxy"

# Offering the resolver role is one shared decision, made in 45-resolver so the
# rules and the watchdog exist in exactly one place. Declining is fine and
# leaves /ip dns untouched.
:global mResolverCandidate "DNSProxy"
:global mResolverAddr "192.168.255.10"
$mRun "modules/45-resolver.rsc"
}
