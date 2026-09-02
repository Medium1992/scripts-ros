# scripts-ros :: modules/90-uninstall.rsc
# Menu entry x. Runs every per-row removal, in reverse dependency order.
#
# It owns no removal logic of its own. Each row already knows how to take
# itself apart, and duplicating that here is how the two copies drift until
# the wholesale uninstall misses something the targeted one handles.
#
# Reverse order is not cosmetic: containers must go before the storage slot
# their root-dir sits on, and the resolver watchdog must go before the
# container it watches.

:global mHdr
:global mSay
:global mOk
:global mRun
:global mYesNo
:global mSkip

$mHdr "Remove everything"

$mSay "  each step asks for its own confirmation, so you can still keep parts."
$mSay "  base settings are handled last and keep DNS, NTP and IPv6 as they are."
$mSay ""

:if ([$mYesNo prompt="Walk through removing everything?"] = false) do={
    $mSkip "cancelled"
} else={

:local steps {
    "modules/60-links-remove.rsc";
    "modules/50-lists-remove.rsc";
    "modules/41-adguard-remove.rsc";
    "modules/40-dnsproxy-remove.rsc";
    "modules/30-mihomo-remove.rsc";
    "modules/20-storage-remove.rsc";
    "modules/10-base-remove.rsc"
}

:local failed 0
:foreach s in=$steps do={
    :if ([$mRun $s] = false) do={ :set failed ($failed + 1) }
}

# The state script is only dropped when there is nothing left for it to
# describe. Deleting it after the operator declined every step would throw away
# their storage slot, resolver and mode choices while leaving the objects those
# choices refer to in place -- the worst of both.
:local leftovers 0
:set leftovers ($leftovers + [:len [/container/find where comment="MihomoProxyRoS" or comment="DNSProxy" or comment="AdGuardHome"]])
:set leftovers ($leftovers + [:len [/routing/table/find where comment="MihomoProxyRoS"]])
:set leftovers ($leftovers + [:len [/system/script/find where comment~"^sros:"]])
:set leftovers ($leftovers + [:len [/interface/veth/find where name="MihomoProxyRoS" or name="DNSProxy" or name="AdGuardHome"]])

:onerror e in={
    :if ([:len [/system/script/find where name="sros_state"]] > 0) do={
        :if ($leftovers = 0) do={
            /system/script/remove [find where name="sros_state"]
            $mOk "state removed, nothing of this project is left"
        } else={
            $mSkip ("state kept: " . $leftovers . " object(s) of this project still installed")
        }
    }
} do={ :put ("  [ !! ] state: " . $e) }

$mSay ""
:if ($failed = 0) do={
    $mSay "  uninstall walk complete"
} else={
    $mSay ("  finished with " . $failed . " failed step(s), see above")
}
$mSay "  anything you chose to keep is still there; row s shows what."

}
