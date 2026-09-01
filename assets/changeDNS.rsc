# scripts-ros :: assets/changeDNS.rsc
# Installed as the script changeDNS and run every 10 seconds by the DNSchange
# scheduler.
#
# Keeps /ip dns pointed at whichever container was chosen as the resolver, and
# falls back the moment that container is not running. Without this the router
# keeps querying a dead address after the container stops, and on a router that
# IS the DNS server that means the whole network loses DNS.
#
# There is exactly ONE of this script, whichever container it is watching. Two
# independent watchdogs -- one for DNSProxy, one for AdGuard Home -- would each
# see the other wrong value and rewrite it, flipping the resolver every ten
# seconds forever. So the target lives in sros_state and is chosen once:
#   resolver       container comment, e.g. AdGuardHome
#   resolver_addr  its address, e.g. 192.168.255.14
# Pointing this at a different container is a state change, not a second copy.
#
# The fallback is plain DNS on port 53, not DoH: Google, Cloudflare and Quad9
# DoH are blocked here, so falling back to them is falling back to nothing, and
# this is the one path that must work with no container and no proxy running.
#   194.85.254.37  NSDI
#   77.88.8.8      Yandex
# Keep in sync with $mFallbackServers in lib.rsc.

:local fallback "194.85.254.37,77.88.8.8"

:global mS
:onerror e in={
    :local fn [:parse [/system/script/get [find where name="sros_state"] source]]
    $fn
} do={
    :log error "changeDNS: cannot read sros_state, standing down"
    :error "no state"
}

:local target ($mS->"resolver")
:local addr ($mS->"resolver_addr")

:if ([:typeof $target] = "nothing" or [:typeof $addr] = "nothing") do={
    :error "no resolver configured"
}
:if ([:len $target] = 0 or [:len $addr] = 0) do={
    # Nothing is supposed to own the resolver. Only undo our own doing.
    :if ([/ip/dns/get servers] = $addr and [:len $addr] > 0) do={
        /ip/dns/set use-doh-server="" verify-doh-cert=no
        /ip/dns/set servers=$fallback
        /ip/dns/cache/flush
        :log warning "changeDNS: no resolver configured, fell back to NSDI and Yandex"
    }
} else={
    :if ([:len [/container/find where comment=$target and running]] > 0) do={
        :if ([/ip/dns/get servers] != $addr) do={
            # DoH takes precedence over servers=, so it has to be cleared first
            # or the container never sees a single query.
            /ip/dns/set use-doh-server="" verify-doh-cert=no
            /ip/dns/set servers=$addr
            /ip/dns/cache/flush
            :log warning ("changeDNS: resolver switched to " . $target)
        }
    } else={
        :if ([/ip/dns/get servers] = $addr) do={
            /ip/dns/set use-doh-server="" verify-doh-cert=no
            /ip/dns/set servers=$fallback
            /ip/dns/cache/flush
            :log warning ("changeDNS: " . $target . " is down, fell back to NSDI and Yandex")
        }
    }
}
