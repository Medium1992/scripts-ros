# scripts-ros :: modules/50-lists-remove.rsc
# Removes the resource scripts and their schedulers.
#
# Your companion lists are asked about separately and default to staying. They
# are the only part of this whole project that represents your own decisions
# rather than ours, and deleting them along with the engine would be exactly
# the surprise the engine/data split exists to prevent.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo
:global mStateSet

$mHdr "Remove resource lists"

:if ([$mYesNo prompt="Remove the resource scripts and their schedulers?"] = false) do={
    $mOk "cancelled"
} else={

:onerror e in={
    :local ids [/system/scheduler/find where name="update_FWD" or name="route_UP"]
    :if ([:len $ids] > 0) do={
        /system/scheduler/remove $ids
        $mOk ([:len $ids] . " scheduler(s) removed")
    }
} do={ $mErr "schedulers" $e }

:local names {"FWD_update";"FWD_update_RU";"IP_MihomoProxyRoS";"route_UP"}
:onerror e in={
    :foreach n in=$names do={
        :local ids [/system/script/find where name=$n]
        :if ([:len $ids] > 0) do={
            /system/script/remove $ids
            $mOk ($n . " removed")
        }
        :local bak [/system/script/find where name=($n . "_bak")]
        :if ([:len $bak] > 0) do={
            /system/script/remove $bak
            $mOk ($n . "_bak removed")
        }
        $mStateSet key=("h_" . $n) value=""
        $mStateSet key=("e_" . $n) value=""
    }
} do={ $mErr "scripts" $e }

:if ([$mYesNo prompt="Also delete YOUR companion lists (FWD_update_list etc)?"]) do={
    :onerror e in={
        :local ids [/system/script/find where comment~"^sros:list"]
        :if ([:len $ids] > 0) do={
            /system/script/remove $ids
            $mOk ([:len $ids] . " companion list(s) deleted")
        }
    } do={ $mErr "companion lists" $e }
} else={
    $mOk "companion lists kept, a reinstall will reuse them"
}

# What these scripts produced is DNS and firewall data, not scripts. It is
# large, slow to delete and harmless to keep, so it is a separate question.
:local fwd [:len [/ip/dns/static/find where type="FWD"]]
:local al [:len [/ip/firewall/address-list/find]]
$mSay ""
$mSay ("  they populated " . $fwd . " FWD records and " . $al . " address-list entries")
:if ([$mYesNo prompt="Delete that data too? (slow, several minutes)"]) do={
    :onerror e in={
        /ip/dns/static/remove [find where type="FWD" and name!="pool.ntp.org"]
        $mOk "FWD records removed"
    } do={ $mErr "fwd records" $e }
} else={
    $mOk "populated data kept"
}

}
