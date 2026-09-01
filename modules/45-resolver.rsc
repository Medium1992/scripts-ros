# scripts-ros :: modules/45-resolver.rsc
# Installs, retargets or removes the resolver watchdog. Not a menu row: rows 40
# and 41 call it after writing their choice into state.
#
# Everything about which container answers DNS for the router lives here, so
# there is one watchdog, one scheduler and one place that knows the failover
# rules -- rather than a near-copy inside every container module that would
# drift the moment one of them is edited.
#
# Expects in state:
#   resolver       container comment, or "" to hand DNS back to the fallback
#   resolver_addr  its address

:global mHdr
:global mOk
:global mSay
:global mErr
:global mFetch
:global mStateGet
:global mFallbackServers

$mHdr "Resolver watchdog"

:local target [$mStateGet "resolver"]

:if ([:len $target] = 0) do={
    :onerror e in={
        :if ([:len [/system/scheduler/find where name="DNSchange"]] > 0) do={
            /system/scheduler/remove [find where name="DNSchange"]
            $mOk "scheduler DNSchange removed"
        }
        :if ([:len [/system/script/find where name="changeDNS"]] > 0) do={
            /system/script/remove [find where name="changeDNS"]
            $mOk "script changeDNS removed"
        }
        # Whatever the watchdog last set, hand DNS back to something that works.
        :if ([/ip/dns/get servers] != $mFallbackServers) do={
            /ip/dns/set use-doh-server="" verify-doh-cert=no
            /ip/dns/set servers=$mFallbackServers
            /ip/dns/cache/flush
            $mOk ("resolver set to " . $mFallbackServers)
        }
    } do={ $mErr "watchdog removal" $e }
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

            # Run it immediately so the operator sees the result now rather
            # than wondering for ten seconds whether it took.
            /system/script/run changeDNS
            $mSay ""
            $mOk ("watching " . $target . " at " . [$mStateGet "resolver_addr"])
            $mOk ("resolver is now " . [/ip/dns/get servers])
            $mSay ("  fallback when it stops: " . $mFallbackServers)
        } do={ $mErr "watchdog install" $e }
    }
}
