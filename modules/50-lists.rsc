# scripts-ros :: modules/50-lists.rsc
# Menu entry 5. Installs and updates the four resource scripts.
#
# Each managed script is engine + data. The engine comes from this repository
# and may be replaced at will. The data -- your list of resources -- is written
# once and then belongs to you; the installer will not touch it again, so
# editing your set of sites never collides with an engine update.
#
# For anyone who edits the engine anyway, a three-way compare decides what to
# do, the same way a merge tool would:
#
#   H_base     hash recorded when we installed it
#   H_local    hash of what is on the router right now
#   H_expected hash of what upstream would install today
#
#   local = base, expected differs  -> clean update, applied silently
#   local differs, expected = base  -> you edited it, left alone
#   both differ                     -> conflict, you are asked

:global mHdr
:global mOk
:global mSay
:global mErr
:global mAsk
:global mYesNo
:global mFetch
:global mHash
:global mStateGet
:global mStateSet

$mHdr "Resource lists"

# name | engine file | companion list script | companion source file
:local managed {
    {"n"="FWD_update";        "e"="lists/engine.rsc";   "l"="FWD_update_list";        "ls"="lists/FWD_update_list.rsc"};
    {"n"="FWD_update_RU";     "e"="lists/engine.rsc";   "l"="FWD_update_RU_list";     "ls"="lists/FWD_update_RU_list.rsc"};
    {"n"="IP_MihomoProxyRoS"; "e"="lists/engine.rsc";   "l"="IP_MihomoProxyRoS_list"; "ls"="lists/IP_MihomoProxyRoS_list.rsc"};
    {"n"="route_UP";          "e"="lists/route_UP.rsc"; "l"="";                       "ls"=""}
}

:foreach m in=$managed do={
    # Deliberately not called "name": inside [find where name=$x] RouterOS
    # resolves a bare variable of that name against the item property instead
    # of the local, and the lookup silently returns the wrong item.
    :local sname ($m->"n")
    :local listName ($m->"l")
    $mSay ""
    $mSay ("  -- " . $sname)

    # ---------------------------------------------------- companion list
    # Written once. If it exists it is the operator list and stays untouched,
    # which is the entire reason engine and data are separate files.
    :if ([:len $listName] > 0) do={
        :if ([:len [/system/script/find where name=$listName]] = 0) do={
            :local lbody [$mFetch ($m->"ls")]
            :if ([:len $lbody] = 0) do={
                $mErr $listName "cannot fetch companion list"
            } else={
                :onerror e in={
                    /system/script/add name=$listName source=$lbody comment="sros:list (yours, never overwritten)"
                    $mOk ($listName . " installed")
                } do={ $mErr $listName $e }
            }
        } else={
            $mOk ($listName . " kept (yours)")
        }
    }

    # ------------------------------------------------------------ engine
    :local ebody [$mFetch ($m->"e")]
    :if ([:len $ebody] = 0) do={
        $mErr $sname "cannot fetch engine"
    } else={
        :local prefix ""
        :if ([:len $listName] > 0) do={ :set prefix (":global rosList \"" . $listName . "\"\n") }
        :local expected ($prefix . $ebody)
        :local hExpected [$mHash $expected]
        :local hBase [$mStateGet ("h_" . $sname)]

        :if ([:len [/system/script/find where name=$sname]] = 0) do={
            :onerror e in={
                /system/script/add name=$sname source=$expected comment="sros:engine"
                $mStateSet key=("h_" . $sname) value=$hExpected
                $mStateSet key=("e_" . $sname) value=[$mHash $ebody]
                $mOk ($sname . " installed")
            } do={ $mErr $sname $e }
        } else={
            :local hLocal [$mHash [/system/script/get [find where name=$sname] source]]

            :if ($hLocal = $hExpected) do={
                $mOk ($sname . " up to date")
                $mStateSet key=("h_" . $sname) value=$hExpected
                $mStateSet key=("e_" . $sname) value=[$mHash $ebody]
            } else={
                :local edited ([:len $hBase] > 0 and $hLocal != $hBase)
                :local upstream ([:len $hBase] = 0 or $hExpected != $hBase)

                :local doWrite false
                :if ($edited and $upstream) do={
                    $mSay ("  [ !! ] " . $sname . ": you edited it AND upstream changed")
                    $mSay "         1) keep mine   2) take upstream (mine saved as _bak)   3) skip"
                    :local c [$mAsk default="1"]
                    :if ($c = "2") do={ :set doWrite true }
                    :if ($c = "1") do={ $mOk ($sname . " kept, upstream ignored") }
                    :if ($c != "1" and $c != "2") do={ $mOk ($sname . " skipped") }
                } else={
                    :if ($edited) do={
                        $mOk ($sname . " edited locally, left alone")
                    } else={
                        :set doWrite true
                    }
                }

                :if ($doWrite) do={
                    :onerror e in={
                        # Always keep the outgoing version. A wrong overwrite
                        # here costs an operator their tuning.
                        :if ([:len [/system/script/find where name=($sname . "_bak")]] > 0) do={
                            /system/script/remove [find where name=($sname . "_bak")]
                        }
                        /system/script/add name=($sname . "_bak") comment="sros:backup" \
                            source=[/system/script/get [find where name=$sname] source]
                        /system/script/set [find where name=$sname] source=$expected
                        $mStateSet key=("h_" . $sname) value=$hExpected
                        $mStateSet key=("e_" . $sname) value=[$mHash $ebody]
                        $mOk ($sname . " updated, previous version kept as " . $sname . "_bak")
                    } do={ $mErr $sname $e }
                }
            }
        }
    }
}

# --------------------------------------------------------------- schedulers
$mSay ""
:onerror e in={
    :if ([:len [/system/scheduler/find where name="update_FWD"]] = 0) do={
        /system/scheduler/add name=update_FWD interval=1d start-time=06:30:00 comment="sros:lists" \
            on-event="/system/script/run FWD_update_RU\r\n/system/script/run FWD_update\r\n/system/script/run IP_MihomoProxyRoS"
        $mOk "scheduler update_FWD daily at 06:30"
    } else={
        $mOk "scheduler update_FWD present"
    }
    :if ([:len [/system/scheduler/find where name="route_UP"]] = 0) do={
        /system/scheduler/add name=route_UP interval=10s comment="sros:lists" on-event="/system/script/run route_UP"
        $mOk "scheduler route_UP every 10s"
    } else={
        $mOk "scheduler route_UP present"
    }
} do={ $mErr "schedulers" $e }

# ------------------------------------------------------------------ run now
# The first run pulls tens of thousands of entries and takes minutes, so it is
# a choice rather than something that happens while you wonder if it hung.
$mSay ""
:if ([$mYesNo prompt="Populate the lists now? (several minutes)"]) do={
    :foreach n in={"FWD_update_RU";"FWD_update";"IP_MihomoProxyRoS"} do={
        :if ([:len [/system/script/find where name=$n]] > 0) do={
            $mSay ("  running " . $n . " ...")
            :onerror e in={ /system/script/run $n } do={ $mErr $n $e }
        }
    }
    $mOk ([:len [/ip/dns/static/find]] . " static DNS entries, " . [:len [/ip/firewall/address-list/find]] . " address-list entries")
} else={
    $mOk "populate skipped, the daily scheduler will do it"
}
