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
    # Give back whatever this container was allocated: a router-side address if
    # it was standalone, a bridge port if it was on the bridge.
    :global mStateGet
    :global mStateSet
    :local gw [$mStateGet ("netgw_AdGuardHome")]
    :if ([:len $gw] > 0) do={
        :local addr [/ip/address/find where address=($gw . "/30")]
        :if ([:len $addr] > 0) do={ /ip/address/remove $addr }
    }
    :local port [/interface/bridge/port/find where interface="AdGuardHome"]
    :if ([:len $port] > 0) do={ /interface/bridge/port/remove $port }
    /interface/list/member/remove [find where interface="AdGuardHome"]
    /interface/veth/remove [find where name="AdGuardHome"]
    $mStateSet key="netaddr_AdGuardHome" value=""
    $mStateSet key="netgw_AdGuardHome" value=""
    $mStateSet key="netmode_AdGuardHome" value=""
    $mOk "mounts, forwarder, veth, bridge port and address removed"
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
