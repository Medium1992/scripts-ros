# scripts-ros :: modules/11-dns.rsc
# DNS forwarders, resolver settings and the static records that let the router
# reach a DoH endpoint before DNS works. Data-driven: adding a forwarder is a
# row in the table below, not another copy of the add/skip dance.

:global mHdr
:global mOk
:global mNeed
:global mErr
:global mFallbackServers

$mHdr "DNS"

# name | doh | dns | verify -- doh and dns are mutually exclusive
:local forwarders {
    {"name"="Google";      "doh"="https://8.8.8.8/dns-query";        "dns"=""; "verify"=true};
    {"name"="CloudFlare";  "doh"="https://1.1.1.1/dns-query";        "dns"=""; "verify"=true};
    {"name"="Quad9";       "doh"="https://9.9.9.9/dns-query";        "dns"=""; "verify"=true};
    {"name"="XBOX";        "doh"="";                                "dns"="111.88.96.50,111.88.96.51"; "verify"=true};
    {"name"="XBOX-DOH";    "doh"="https://xbox-dns.ru/dns-query";    "dns"=""; "verify"=true};
    {"name"="Yandex";      "doh"="";                                "dns"="77.88.8.8,77.88.8.1";       "verify"=false};
    {"name"="Google8";     "doh"="";                                "dns"="8.8.8.8";                   "verify"=false};
    {"name"="NSDI";        "doh"="";                                "dns"="194.85.254.37";             "verify"=false};
    {"name"="Fallback";    "doh"="";                                "dns"="194.85.254.37,77.88.8.8";   "verify"=false}
}

:onerror e in={
    :foreach f in=$forwarders do={
        :local label ("forwarder " . ($f->"name"))
        :if ([$mNeed id=[/ip/dns/forwarders/find where name=($f->"name")] name=$label]) do={
            :if ([:len ($f->"doh")] > 0) do={
                /ip/dns/forwarders/add name=($f->"name") doh-servers=($f->"doh") verify-doh-cert=($f->"verify")
            } else={
                /ip/dns/forwarders/add name=($f->"name") dns-servers=($f->"dns") verify-doh-cert=($f->"verify")
            }
            $mOk $label
        }
    }
} do={ $mErr "forwarders" $e }

# The container and the DNS resolver both need the built-in CA bundle, or every
# DoH handshake and every image pull fails with a certificate error.
:onerror e in={
    /certificate/settings/set builtin-trust-store=dns,container
    $mOk "trust-store dns,container"
} do={ $mErr "trust-store" $e }

:onerror e in={
    # No public DoH here, by name or by IP. Google, Cloudflare and Quad9
    # DoH are blocked in the target region, and pointing at them by raw
    # address stopped working too. This setting is what the router
    # resolves with BEFORE any proxy exists -- during this very install --
    # so it has to be something that answers on a plain connection.
    #
    # The DoH forwarders defined above stay useful: traffic through them
    # goes out via the proxy once it is up, and row 40 or 41 can take the
    # resolver over later. This is only the floor.
    /ip/dns/set allow-remote-requests=yes cache-max-ttl=1d cache-size=15000KiB \
        doh-max-concurrent-queries=500 doh-max-server-connections=10 \
        use-doh-server="" verify-doh-cert=no servers=$mFallbackServers
    $mOk ("resolver settings, upstream " . $mFallbackServers)
} do={ $mErr "resolver" $e }

# Bootstrap records. Without these the router cannot resolve the DoH hostname
# it is supposed to use for resolving, which is the classic chicken and egg.
:local statics {
    {"name"="dns.google";        "addr"="8.8.8.8";        "note"="DNS Google"};
    {"name"="dns.google";        "addr"="8.8.4.4";        "note"="DNS Google"};
    {"name"="cloudflare-dns.com";"addr"="104.16.248.249"; "note"="DNS CloudFlare"};
    {"name"="cloudflare-dns.com";"addr"="104.16.249.249"; "note"="DNS CloudFlare"};
    {"name"="dns.quad9.net";     "addr"="9.9.9.9";        "note"="DNS Quad9"};
    {"name"="dns.quad9.net";     "addr"="149.112.112.112";"note"="DNS Quad9"};
    {"name"="xbox-dns.ru";       "addr"="111.88.96.55";   "note"="XBOX DNS"}
}

:onerror e in={
    :foreach s in=$statics do={
        :local label ("static " . ($s->"name") . " " . ($s->"addr"))
        :if ([$mNeed id=[/ip/dns/static/find where name=($s->"name") and address=($s->"addr")] name=$label]) do={
            /ip/dns/static/add name=($s->"name") address=($s->"addr") comment=($s->"note") type=A
            $mOk $label
        }
    }
} do={ $mErr "static records" $e }

# NTP hostnames must resolve through plain DNS, not through the proxy, or the
# clock never sets and every TLS handshake afterwards fails on cert validity.
:onerror e in={
    :if ([$mNeed id=[/ip/dns/static/find where name="pool.ntp.org"] name="static pool.ntp.org -> Fallback"]) do={
        /ip/dns/static/add name=pool.ntp.org forward-to=Fallback match-subdomain=yes type=FWD
        $mOk "static pool.ntp.org -> Fallback"
    }
} do={ $mErr "ntp forward" $e }
