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
:global mSkip
:global mYesNo
:global mStateSet

$mHdr "Remove resource lists"

:if ([$mYesNo prompt="Remove the resource scripts and their schedulers?"] = false) do={
    $mSkip "cancelled"
} else={

:global mPickTags do={
    :local tags [:toarray ""]
    :foreach ln in={"FWD_update_list";"FWD_update_RU_list";"IP_MihomoProxyRoS_list"} do={
        :if ([:len [/system/script/find where name=$ln]] > 0) do={
            :onerror e in={
                :global rosSets
                :set rosSets [:toarray ""]
                :local fn [:parse [/system/script/get [find where name=$ln] source]]
                $fn
                :foreach set in=$rosSets do={
                    :foreach item in=($set->"items") do={
                        # "geoipv4/telegram" is commented as "telegram": the
                        # fragment path is not part of the name it writes.
                        :local nm $item
                        :local cut [:find $nm "/"]
                        :while ([:typeof $cut] = "num") do={
                            :set nm [:pick $nm ($cut + 1) [:len $nm]]
                            :set cut [:find $nm "/"]
                        }
                        :set tags ($tags, $nm)
                    }
                }
            } do={}
        }
    }
    :return $tags
}
:global mPickTags

# Collected FIRST, before anything is removed. The fragment names live in the
# companion lists, and a later step offers to delete those -- read them after
# that and there is nothing left to match against, so the data this loader
# brought in could never be found again.
:local tags [$mPickTags]
:local fwdOurs [:toarray ""]
:local alOurs [:toarray ""]
:foreach t in=$tags do={
    :foreach d in=[/ip/dns/static/find where comment=$t] do={ :set fwdOurs ($fwdOurs, $d) }
    :foreach a in=[/ip/firewall/address-list/find where comment=$t] do={ :set alOurs ($alOurs, $a) }
}


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
# large, slow to delete and harmless to keep, so it is a separate question --
# and a careful one. An earlier version removed every FWD record on the router
# and took a tester's own hand-made entries with it.
#
# The fragments comment every entry with the name of the fragment that brought
# it in ("category-gov-ru", "telegram", "deepl"), while a record added by hand
# has no comment or one of its own. So the names are read back out of the
# companion lists still on this router, and only entries carrying exactly those
# comments are offered for deletion. Nothing else is counted or touched.
$mSay ""
$mSay ("  the loader brought in " . [:len $fwdOurs] . " DNS record(s) and " . [:len $alOurs] . " address-list entry/entries")
$mSay ("  (matched against " . [:len $tags] . " fragment name(s) from your companion lists)")
:local otherFwd ([:len [/ip/dns/static/find where type="FWD"]] - [:len $fwdOurs])
:if ($otherFwd > 0) do={
    $mSay ("  " . $otherFwd . " other FWD record(s) are not ours and stay untouched")
}

:if (([:len $fwdOurs] + [:len $alOurs]) = 0) do={
    $mSkip "nothing of ours to remove"
} else={
    :if ([$mYesNo prompt="Delete that data too? (slow, several minutes)"]) do={
        :onerror e in={
            :if ([:len $fwdOurs] > 0) do={
                /ip/dns/static/remove $fwdOurs
                $mOk ([:len $fwdOurs] . " DNS record(s) removed")
            }
            :if ([:len $alOurs] > 0) do={
                /ip/firewall/address-list/remove $alOurs
                $mOk ([:len $alOurs] . " address-list entry/entries removed")
            }
        } do={ $mErr "populated data" $e }
    } else={
        $mSkip "populated data kept"
    }
}

}
