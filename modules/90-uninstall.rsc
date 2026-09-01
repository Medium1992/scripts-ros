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

$mHdr "Remove everything"

$mSay "  each step asks for its own confirmation, so you can still keep parts."
$mSay "  base settings are handled last and keep DNS, NTP and IPv6 as they are."
$mSay ""

:if ([$mYesNo prompt="Walk through removing everything?"] = false) do={
    $mOk "cancelled"
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

# The state script is the last thing to go: the removals above read it.
:onerror e in={
    :if ([:len [/system/script/find where name="sros_state"]] > 0) do={
        /system/script/remove [find where name="sros_state"]
        $mOk "state removed"
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
