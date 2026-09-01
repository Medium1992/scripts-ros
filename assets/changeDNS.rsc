# scripts-ros :: assets/changeDNS.rsc
# Installed as the script changeDNS and run every 10 seconds by the DNSchange
# scheduler.
#
# The router points /ip dns at the DNSProxy container while it is running, and
# falls back the moment it is not. Without this the router keeps querying
# 192.168.255.10 after the container stops and the whole network loses DNS --
# which on a router that IS the DNS server means everything stops.
#
# The fallback is plain DNS on port 53, not DoH. Google, Cloudflare and Quad9
# DoH are blocked here, so falling back to them is falling back to nothing;
# that is the one path where the resolver has to work with no proxy, no
# container and no help.
#   194.85.254.37  NSDI
#   77.88.8.8      Yandex
# Keep this list in sync with $mFallbackServers in lib.rsc.
#
# Both directions flush the cache, otherwise answers from the previous resolver
# survive the switch and mask it.

:local proxyAddr "192.168.255.10"
:local fallback "194.85.254.37,77.88.8.8"

:if ([:len [/container/find where comment="DNSProxy" and running]] > 0) do={
    :if ([/ip/dns/get servers] != $proxyAddr) do={
        # DoH takes precedence over servers=, so it has to go first or the
        # container never sees a query.
        /ip/dns/set use-doh-server="" verify-doh-cert=no
        /ip/dns/set servers=$proxyAddr
        /ip/dns/cache/flush
        :log warning "changeDNS: resolver switched to DNSProxy"
    }
} else={
    :if ([/ip/dns/get servers] = $proxyAddr) do={
        /ip/dns/set use-doh-server="" verify-doh-cert=no
        /ip/dns/set servers=$fallback
        /ip/dns/cache/flush
        :log warning "changeDNS: DNSProxy is down, resolver fell back to NSDI and Yandex"
    }
}
