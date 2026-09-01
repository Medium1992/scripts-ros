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
# The fallback is whatever row 10 settled on, carried in the same state file:
#   fb_doh      DoH URL, or empty for plain DNS only
#   fb_servers  plain servers, kept behind DoH as well so a failed DoH query
#               still resolves
# Defaults here match lib.rsc for a router where row 10 was never run.
:local fbDoh ""
:local fbServers "77.88.8.8,77.88.8.1"

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
:if ([:typeof ($mS->"fb_servers")] != "nothing") do={
    :if ([:len ($mS->"fb_servers")] > 0) do={ :set fbServers ($mS->"fb_servers") }
}
:if ([:typeof ($mS->"fb_doh")] != "nothing") do={ :set fbDoh ($mS->"fb_doh") }

:local applyFallback do={
    :if ([:len $doh] > 0) do={
        /ip/dns/set use-doh-server=$doh verify-doh-cert=yes
    } else={
        /ip/dns/set use-doh-server="" verify-doh-cert=no
    }
    /ip/dns/set servers=$servers
    /ip/dns/cache/flush
}

:if ([:typeof $target] = "nothing" or [:typeof $addr] = "nothing") do={
    :error "no resolver configured"
}
:if ([:len $target] = 0 or [:len $addr] = 0) do={
    # Nothing is supposed to own the resolver. Only undo our own doing.
    :if ([/ip/dns/get servers] = $addr and [:len $addr] > 0) do={
        $applyFallback doh=$fbDoh servers=$fbServers
        :log warning "changeDNS: no resolver configured, fell back"
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
            $applyFallback doh=$fbDoh servers=$fbServers
            :log warning ("changeDNS: " . $target . " is down, fell back")
        }
    }
}
