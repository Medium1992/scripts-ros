# scripts-ros :: modules/11-dns.rsc
# DNS forwarders, resolver settings and the static records that let the router
# reach a DoH endpoint before DNS works. Data-driven: adding a forwarder is a
# row in the table below, not another copy of the add/skip dance.

:global mHdr
:global mOk
:global mNeed
:global mSkip
:global mErr
:global mSay
:global mAsk

$mHdr "DNS"

# The decision comes first, before anything is created, so the module reads as
# "here is what I am about to do" rather than springing a question halfway
# through a wall of output.
:global mFallbackLoad
:global mFallbackApply
:global mFallbackDesc
:global mFallbackDoh
:global mFallbackServers
:global mStateSet
$mFallbackLoad

:local arch [/system/resource/get architecture-name]
$mSay ""
$mSay "  First: what should this router resolve names with, until a container"
$mSay "  or a proxy takes the job over? This is also what it falls back to if"
$mSay "  one of those stops."
$mSay ""
:if ($arch = "arm64" or $arch = "x86_64") do={
    $mSay "   1) Yandex DoH, plain Yandex behind it   <- suggested on this hardware"
    $mSay "   2) Yandex plain DNS only"
} else={
    $mSay "   1) Yandex DoH, plain Yandex behind it"
    $mSay ("   2) Yandex plain DNS only               <- suggested on " . $arch)
    $mSay "      (HTTP/2 for DoH is ARM64 and x86/CHR only, so DoH may not answer)"
}
$mSay "   3) Quad9 DoH, plain Quad9 behind it"
$mSay "   4) NSDI first, Yandex behind it (domestic names resolve first)"
$mSay ("  Enter keeps what is set now: " . [$mFallbackDesc])
:local fbPick [$mAsk default=""]

:if ($fbPick = "1") do={ :set mFallbackDoh "https://common.dot.dns.yandex.net/dns-query" ; :set mFallbackServers "77.88.8.8,77.88.8.1" }
:if ($fbPick = "2") do={ :set mFallbackDoh ""                                            ; :set mFallbackServers "77.88.8.8,77.88.8.1" }
:if ($fbPick = "3") do={ :set mFallbackDoh "https://9.9.9.9/dns-query"                   ; :set mFallbackServers "9.9.9.9,149.112.112.112" }
:if ($fbPick = "4") do={ :set mFallbackDoh ""                                            ; :set mFallbackServers "194.85.254.37,77.88.8.8" }
:if ([:len $fbPick] > 0) do={
    $mStateSet key="fb_doh" value=$mFallbackDoh
    $mStateSet key="fb_servers" value=$mFallbackServers
}
$mSay ("  -> " . [$mFallbackDesc])
$mSay ""
$mSay "  Now setting up the forwarders, the resolver and the bootstrap records."


# One provider, up to three forwarders, so the variant is readable from the
# name alone and nobody has to open the config to find out what they get:
#
#   <Name>            DoH with certificate verification -- the default
#   <Name>_noverify   the same DoH with verification off
#   <Name>_udp        plain DNS on port 53
#
# _noverify exists because RouterOS cannot validate every valid certificate:
# its bundled root set is missing the CA that signs the Cloudflare chain. Run
# 16-cacert and the plain <Name> works, at which point _noverify is only a
# diagnostic. Encryption without authentication does not stop an on-path
# attacker, which is the one DoH is for, so it is never the default.
:local providers {
    {"name"="Google";         "doh"="https://8.8.8.8/dns-query";                    "udp"="8.8.8.8,8.8.4.4"};
    {"name"="GoogleHost";     "doh"="https://dns.google/dns-query";                 "udp"=""};
    {"name"="CloudFlare";     "doh"="https://1.1.1.1/dns-query";                    "udp"="1.1.1.1,1.0.0.1"};
    {"name"="CloudFlareHost"; "doh"="https://one.one.one.one/dns-query";            "udp"=""};
    {"name"="Quad9";          "doh"="https://9.9.9.9/dns-query";                    "udp"="9.9.9.9,149.112.112.112"};
    {"name"="Quad9Host";      "doh"="https://dns.quad9.net/dns-query";              "udp"=""};
    {"name"="Yandex";         "doh"="https://common.dot.dns.yandex.net/dns-query";  "udp"="77.88.8.8,77.88.8.1"};
    {"name"="XBOX";           "doh"="https://xbox-dns.ru/dns-query";                "udp"="111.88.96.50,111.88.96.51"};
    {"name"="NSDI";           "doh"="";                                             "udp"="194.85.254.37"};
    {"name"="Fallback";       "doh"="";                                             "udp"="77.88.8.8,77.88.8.1,194.85.254.37"}
}

# Bulk work reports a total, not a line per item. Twenty-three "already there"
# lines on every rerun bury the two lines that actually mattered.
:onerror e in={
    :local made 0
    :local kept 0
    :foreach pr in=$providers do={
        :local base ($pr->"name")
        :if ([:len ($pr->"doh")] > 0) do={
            :if ([:len [/ip/dns/forwarders/find where name=$base]] = 0) do={
                /ip/dns/forwarders/add name=$base doh-servers=($pr->"doh") verify-doh-cert=yes
                :set made ($made + 1)
            } else={ :set kept ($kept + 1) }
            :local nv ($base . "_noverify")
            :if ([:len [/ip/dns/forwarders/find where name=$nv]] = 0) do={
                /ip/dns/forwarders/add name=$nv doh-servers=($pr->"doh") verify-doh-cert=no
                :set made ($made + 1)
            } else={ :set kept ($kept + 1) }
        }
        :if ([:len ($pr->"udp")] > 0) do={
            :local up ($base . "_udp")
            :if ([:len [/ip/dns/forwarders/find where name=$up]] = 0) do={
                /ip/dns/forwarders/add name=$up dns-servers=($pr->"udp") verify-doh-cert=no
                :set made ($made + 1)
            } else={ :set kept ($kept + 1) }
        }
    }
    :if ($made > 0) do={
        $mOk ($made . " forwarder(s) added, " . $kept . " already present")
    } else={
        $mSkip ("all " . $kept . " forwarders already present")
    }
} do={ $mErr "forwarders" $e }

# DoH over HTTP/2 arrived in 7.23 for ARM64 and x86/CHR only. Elsewhere DoH is
# HTTP/1.1, and an endpoint that insists on HTTP/2 will never answer -- which
# looks like a broken forwarder rather than an unsupported platform. Say so,
# and point at the module that measures it instead of guessing per provider.
:local arch [/system/resource/get architecture-name]
:if ($arch != "arm64" and $arch != "x86_64") do={
    $mSay ""
    $mSay ("  [ !! ] " . $arch . ": HTTP/2 for DoH is ARM64 and x86/CHR only.")
    $mSay "         Some DoH forwarders above may never answer here."
    $mSay "         Run row 17 to find out which, and prefer the _udp variants."
}

# The resolver itself, now that the answer is known.
:onerror e in={
    /ip/dns/set allow-remote-requests=yes cache-max-ttl=1d cache-size=15000KiB         doh-max-concurrent-queries=500 doh-max-server-connections=10
    $mFallbackApply
    $mOk ("resolver: " . [$mFallbackDesc])
} do={ $mErr "resolver" $e }

# builtin-trust-store takes either a group keyword or an explicit service list,
# and the stock value is the keyword "default". Measured on 7.24.1 with a
# verified fetch of this repository:
#
#   default     ok      already covers fetch, dns and container
#   all         ok
#   untrusted   fails   nothing is trusted
#
# So on an untouched router there is nothing to do here, and assigning the
# three services this project cares about would replace a keyword covering
# eleven of them -- taking trust away rather than adding it. Only a list that
# has genuinely been narrowed is worth touching, and then only by appending.
# (This lab router read container,dns after the older script, which is exactly
# why a verified fetch failed on it.)
:onerror e in={
    :local ts [:tostr [/certificate/settings/get builtin-trust-store]]
    :if ($ts = "default" or $ts = "all") do={
        $mSkip ("trust store is the stock '" . $ts . "' group, leaving it alone")
    } else={
        :local missing ""
        :foreach svc in={"dns";"container";"fetch"} do={
            :if ([:typeof [:find $ts $svc]] != "num") do={
                :if ([:len $missing] = 0) do={ :set missing $svc } else={ :set missing ($missing . "," . $svc) }
            }
        }
        :if ([:len $missing] = 0) do={
            $mSkip ("trust store already covers dns, container and fetch (" . $ts . ")")
        } else={
            :if ($ts = "untrusted") do={
                # "untrusted" is not a list to append to; it means nothing is
                # trusted at all, and the stock group is the right answer.
                /certificate/settings/set builtin-trust-store=default
                $mOk "trust store was 'untrusted', set to the stock 'default' group"
            } else={
                /certificate/settings/set builtin-trust-store=($ts . "," . $missing)
                $mOk ("trust store extended with " . $missing . ", now " . [:tostr [/certificate/settings/get builtin-trust-store]])
            }
            # Takes a second or two to become usable; a verified fetch
            # immediately after this still fails.
            :delay 3
        }
    }
} do={ $mErr "trust-store" $e }



# Bootstrap records. Without these the router cannot resolve the DoH hostname
# it is supposed to use for resolving, which is the classic chicken and egg.
:local statics {
    {"name"="dns.google";        "addr"="8.8.8.8";        "note"="DNS Google"};
    {"name"="dns.google";        "addr"="8.8.4.4";        "note"="DNS Google"};
    {"name"="cloudflare-dns.com";"addr"="104.16.248.249"; "note"="DNS CloudFlare"};
    {"name"="cloudflare-dns.com";"addr"="104.16.249.249"; "note"="DNS CloudFlare"};
    {"name"="one.one.one.one";   "addr"="1.1.1.1";        "note"="DNS CloudFlare"};
    {"name"="common.dot.dns.yandex.net"; "addr"="77.88.8.8"; "note"="DNS Yandex"};
    {"name"="one.one.one.one";   "addr"="1.0.0.1";        "note"="DNS CloudFlare"};
    {"name"="dns.quad9.net";     "addr"="9.9.9.9";        "note"="DNS Quad9"};
    {"name"="dns.quad9.net";     "addr"="149.112.112.112";"note"="DNS Quad9"};
    {"name"="xbox-dns.ru";       "addr"="111.88.96.55";   "note"="XBOX DNS"}
}

:onerror e in={
    :local made 0
    :local kept 0
    :foreach rec in=$statics do={
        :if ([:len [/ip/dns/static/find where name=($rec->"name") and address=($rec->"addr")]] = 0) do={
            /ip/dns/static/add name=($rec->"name") address=($rec->"addr") comment=($rec->"note") type=A
            :set made ($made + 1)
        } else={ :set kept ($kept + 1) }
    }
    :if ($made > 0) do={
        $mOk ($made . " bootstrap record(s) added, " . $kept . " already present")
    } else={
        $mSkip ("all " . $kept . " bootstrap records already present")
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
