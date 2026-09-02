# scripts-ros :: modules/40-dnsproxy-remove.rsc
# Removes DNSProxy.
#
# The watchdog goes first and the resolver is restored before the container is
# touched. Reverse that order and changeDNS fires during the removal, points
# /ip dns at an address that is about to stop answering, and the network loses
# DNS at exactly the moment you are busy.

:global mHdr
:global mOk
:global mErr
:global mSkip
:global mYesNo
:global mFallbackLoad
:global mFallbackApply
:global mFallbackDesc
:global mStateGet
:global mStateSet
:global mRun

$mHdr "Remove DNSProxy"

:if ([$mYesNo prompt="Remove the DNSProxy container and its resolver watchdog?"] = false) do={
    $mSkip "cancelled"
} else={

# Hand the resolver back before touching the container: clearing state first
# means the fallback is restored while the container is still alive, instead of
# the scheduler finding a dead address in the middle of the removal.
:if ([$mStateGet "resolver"] = "DNSProxy") do={
    $mStateSet key="resolver" value=""
    $mStateSet key="resolver_addr" value=""
    :global mResolverCandidate ""
    :global mResolverAddr ""
    $mRun "modules/45-resolver.rsc"
} else={
    $mOk "resolver was not pointed here"
}


:onerror e in={
    :local job ("DNSProxy_repull")
    :if ([:len [/system/script/find where name=$job]] > 0) do={
        /system/scheduler/remove [find where name=$job]
        /system/script/remove [find where name=$job]
        $mOk ($job . " removed")
    }
    :local ids [/container/find where comment="DNSProxy"]
    :if ([:len $ids] > 0) do={
        :onerror e2 in={ /container/stop $ids } do={}
        :local w 0
        :while ([:len [/container/find where comment="DNSProxy" and stopped]] = 0 and $w < 30) do={
            :delay 1
            :set w ($w + 1)
        }
        /container/remove $ids
        $mOk "container removed"
    }
} do={ $mErr "container" $e }

:onerror e in={
    :local fwd [/ip/dns/static/find where forward-to="DNSProxy"]
    :if ([:len $fwd] > 0) do={ /ip/dns/static/remove $fwd }
    /ip/dns/forwarders/remove [find where name="DNSProxy"]
    /ip/address/remove [find where address="192.168.255.9/30"]
    /interface/list/member/remove [find where interface="DNSProxy"]
    /interface/veth/remove [find where name="DNSProxy"]
    $mOk "forwarder, veth and address removed"
} do={ $mErr "network" $e }

}
