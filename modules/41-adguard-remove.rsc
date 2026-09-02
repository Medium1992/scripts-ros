# scripts-ros :: modules/41-adguard-remove.rsc
# Removes AdGuard Home.
#
# The two mounted directories hold the filter configuration and the query log.
# They survive by default: they are the part that took effort to set up, and
# they cost nothing to keep.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mSkip
:global mYesNo
:global mFallbackLoad
:global mFallbackApply
:global mFallbackDesc
:global mStateGet
:global mStateSet
:global mRun

$mHdr "Remove AdGuard Home"

:if ([$mYesNo prompt="Remove the AdGuard Home container?"] = false) do={
    $mSkip "cancelled"
} else={

# Hand the resolver back before touching the container: clearing state first
# means the fallback is restored while the container is still alive, instead of
# the scheduler finding a dead address in the middle of the removal.
:if ([$mStateGet "resolver"] = "AdGuardHome") do={
    $mStateSet key="resolver" value=""
    $mStateSet key="resolver_addr" value=""
    :global mResolverCandidate ""
    :global mResolverAddr ""
    $mRun "modules/45-resolver.rsc"
} else={
    $mOk "resolver was not pointed here"
}


:onerror e in={
    :local job ("AdGuardHome_repull")
    :if ([:len [/system/script/find where name=$job]] > 0) do={
        /system/scheduler/remove [find where name=$job]
        /system/script/remove [find where name=$job]
        $mOk ($job . " removed")
    }
    :local ids [/container/find where comment="AdGuardHome"]
    :if ([:len $ids] > 0) do={
        :onerror e2 in={ /container/stop $ids } do={}
        :local w 0
        :while ([:len [/container/find where comment="AdGuardHome" and stopped]] = 0 and $w < 30) do={
            :delay 1
            :set w ($w + 1)
        }
        /container/remove $ids
        $mOk "container removed"
    }
} do={ $mErr "container" $e }

:onerror e in={
    :local mnt [/container/mounts/find where list="AdGuardHome"]
    :if ([:len $mnt] > 0) do={ /container/mounts/remove $mnt }
    :local fwd [/ip/dns/static/find where forward-to="AdGuardHome"]
    :if ([:len $fwd] > 0) do={ /ip/dns/static/remove $fwd }
    /ip/dns/forwarders/remove [find where name="AdGuardHome"]
    /ip/address/remove [find where address="192.168.255.13/30"]
    /interface/list/member/remove [find where interface="AdGuardHome"]
    /interface/veth/remove [find where name="AdGuardHome"]
    $mOk "mounts, forwarder, veth and address removed"
} do={ $mErr "network" $e }

:if ([$mYesNo prompt="Also delete the AdGuard config and query log directories?"]) do={
    :onerror e in={
        :local dirs [/file/find where name~"^adguard_work" or name~"^adguard_conf"]
        :if ([:len $dirs] > 0) do={
            /file/remove $dirs
            $mOk ([:len $dirs] . " adguard directory/ies deleted")
        } else={
            $mSkip "no adguard directories to delete"
        }
    } do={ $mErr "directories" $e }
} else={
    $mSay "  /adguard_conf/ and /adguard_work/ kept, a reinstall picks them up"
}

}
