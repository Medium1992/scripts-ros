# scripts-ros :: modules/45-resolver.rsc
# Owns everything about which container answers DNS for the router. Not a menu
# row: rows 40 and 41 set two globals and call it.
#
#   $mResolverCandidate  container comment offering itself, "" to just tear down
#   $mResolverAddr       its address
#
# Putting the question here rather than in each container module means there is
# one copy of the failover rules, one watchdog and one scheduler. Two watchdogs
# would each read the other value as wrong and rewrite it every ten seconds.
#
# Nothing here is assumed. Making a container the router resolver is a real
# change to how the whole network resolves names, so it is always a question,
# the answer no is a first-class outcome, and declining leaves /ip dns exactly
# as it was. A container is perfectly useful without owning the resolver --
# point selected domains at it with a DNS FWD rule instead.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo
:global mFetch
:global mStateGet
:global mStateSet
:global mFallbackServers
:global mResolverCandidate
:global mResolverAddr

$mHdr "Router resolver"

:local owner [$mStateGet "resolver"]
:local cand ""
:local addr ""
:if ([:typeof $mResolverCandidate] != "nothing") do={ :set cand $mResolverCandidate }
:if ([:typeof $mResolverAddr] != "nothing") do={ :set addr $mResolverAddr }

# ------------------------------------------------------------- decide
:local wanted $owner
:local wantedAddr [$mStateGet "resolver_addr"]

:if ([:len $cand] = 0) do={
    # Called from a removal: state was already cleared by the caller.
    :set wanted ""
    :set wantedAddr ""
} else={
    $mSay ""
    :if ($owner = $cand) do={
        $mSay ("  " . $cand . " is currently the router resolver.")
        :if ([$mYesNo prompt="Release the resolver back to the fallback servers?"]) do={
            :set wanted ""
            :set wantedAddr ""
        } else={
            $mOk ($cand . " stays the resolver")
        }
    } else={
        :if ([:len $owner] > 0) do={
            $mSay ("  [ !! ] " . $owner . " currently owns the router resolver.")
            $mSay "         Only one container can own it: two watchdogs would"
            $mSay "         overwrite each other every ten seconds."
            :if ([$mYesNo prompt=("Hand the resolver to " . $cand . " instead?")]) do={
                :set wanted $cand
                :set wantedAddr $addr
            }
        } else={
            $mSay ("  " . $cand . " can become the routers resolver, with automatic")
            $mSay ("  fallback to " . $mFallbackServers . " whenever it is not running.")
            $mSay "  Answering no leaves /ip dns untouched -- the container still works,"
            $mSay "  you just send it the domains you choose instead of everything."
            :if ([$mYesNo prompt=("Make " . $cand . " the router resolver?")]) do={
                :set wanted $cand
                :set wantedAddr $addr
            }
        }
    }
}

:if ($wanted = $owner and [:len $cand] > 0 and $wanted != "") do={
    # Nothing changed and the watchdog is already in place.
    $mSay ("  forward domains to it with: /ip/dns/static/add name=<domain> type=FWD forward-to=" . $cand . " match-subdomain=yes")
} else={

$mStateSet key="resolver" value=$wanted
$mStateSet key="resolver_addr" value=$wantedAddr

# --------------------------------------------------------- apply
:if ([:len $wanted] = 0) do={
    :onerror e in={
        :if ([:len [/system/scheduler/find where name="DNSchange"]] > 0) do={
            /system/scheduler/remove [find where name="DNSchange"]
            $mOk "scheduler DNSchange removed"
        }
        :if ([:len [/system/script/find where name="changeDNS"]] > 0) do={
            /system/script/remove [find where name="changeDNS"]
            $mOk "script changeDNS removed"
        }
        # Only correct what the watchdog itself set. If the operator never let
        # a container take the resolver, /ip dns is theirs and stays theirs.
        :if ([:len $owner] > 0) do={
            /ip/dns/set use-doh-server="" verify-doh-cert=no
            /ip/dns/set servers=$mFallbackServers
            /ip/dns/cache/flush
            $mOk ("resolver set to " . $mFallbackServers)
        } else={
            $mOk "/ip dns left untouched"
        }
    } do={ $mErr "watchdog removal" $e }
    :if ([:len $cand] > 0) do={
        $mSay ("  forward domains to it with: /ip/dns/static/add name=<domain> type=FWD forward-to=" . $cand . " match-subdomain=yes")
    }
} else={
    :local body [$mFetch "assets/changeDNS.rsc"]
    :if ([:len $body] = 0) do={
        $mErr "changeDNS" "could not fetch assets/changeDNS.rsc"
    } else={
        :onerror e in={
            :if ([:len [/system/script/find where name="changeDNS"]] = 0) do={
                /system/script/add name=changeDNS source=$body comment="sros:resolver"
            } else={
                /system/script/set [find where name="changeDNS"] source=$body
            }
            $mOk "script changeDNS"
            :if ([:len [/system/scheduler/find where name="DNSchange"]] = 0) do={
                /system/scheduler/add name=DNSchange interval=10s comment="sros:resolver" \
                    on-event="/system/script/run changeDNS"
                $mOk "scheduler DNSchange every 10s"
            } else={
                $mOk "scheduler DNSchange present"
            }
            # Run it now so the result is visible immediately instead of after
            # ten seconds of wondering whether it took.
            /system/script/run changeDNS
            $mOk ("watching " . $wanted . " at " . $wantedAddr)
            # The watchdog only points /ip dns at a container that is actually
            # running, so on a fresh install this is often still the fallback.
            # Say which case it is instead of printing an empty value.
            :if ([:len [/container/find where comment=$wanted and running]] > 0) do={
                $mOk ("resolver is now " . [/ip/dns/get servers])
            } else={
                $mOk ($wanted . " is not running yet, resolver stays on " . [/ip/dns/get servers])
                $mSay "  it will switch over within 10s of the container starting"
            }
            $mSay ("  fallback when it stops: " . $mFallbackServers)
        } do={ $mErr "watchdog install" $e }
    }
}

}
