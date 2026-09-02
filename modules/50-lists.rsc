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
:global mSkip
:global mStateGet
:global mStateSet

$mHdr "Resource lists"

# name | engine file | companion list script | companion source file
# n  installed script name          l   companion list script
# e  engine file in this repository  ls  companion source file
# fwd  true when the list forwards domains to a DNS forwarder, and the
#      operator should get to choose which one
# def  the forwarder to offer first
:local managed {
    {"n"="FWD_update";        "e"="lists/engine.rsc";   "l"="FWD_update_list";        "ls"="lists/FWD_update_list.rsc";        "fwd"=true;  "def"="MihomoProxyRoS"};
    {"n"="FWD_update_RU";     "e"="lists/engine.rsc";   "l"="FWD_update_RU_list";     "ls"="lists/FWD_update_RU_list.rsc";     "fwd"=true;  "def"="Yandex"};
    {"n"="IP_MihomoProxyRoS"; "e"="lists/engine.rsc";   "l"="IP_MihomoProxyRoS_list"; "ls"="lists/IP_MihomoProxyRoS_list.rsc"; "fwd"=false; "def"=""};
    {"n"="route_UP";          "e"="lists/route_UP.rsc"; "l"="";                       "ls"="";                                 "fwd"=false; "def"=""}
}

# Offer the forwarders that actually exist on THIS router, which is the point:
# by the time this runs, rows 40 and 41 may have added DNSProxy or AdGuardHome,
# and sending a domain list at one of them is a perfectly good setup. Hardcoding
# MihomoProxyRoS would hide that.
# Offer the forwarders that exist on THIS router, but not all twenty-five of
# them. The _noverify and _udp variants are diagnostic and last-resort; nobody
# points a domain list at one on purpose, and listing them makes the reader
# scroll past two dozen lines to find the three that matter. They are one
# keystroke away.
:global mPickFwd do={
    :global mSay
    :global mPad
    :local short [:toarray ""]
    :local full [:toarray ""]

    :foreach f in=[/ip/dns/forwarders/find] do={
        :local fname [/ip/dns/forwarders/get $f name]
        :set full ($full, $fname)
        :local variant false
        :if ([:typeof [:find $fname "_noverify"]] = "num") do={ :set variant true }
        :if ([:typeof [:find $fname "_udp"]] = "num") do={ :set variant true }
        :if ($variant = false) do={ :set short ($short, $fname) }
    }
    :if ([:len $full] = 0) do={ :return $default }

    :local names $short
    :local showingAll false
    :while (true) do={
        $mSay ""
        $mSay ("  where should " . $list . " send its domains?")
        :local i 1
        :foreach n in=$names do={
            :local hint ""
            # A forwarder pointing into the container link network is one of
            # ours -- usually the answer -- so say so instead of leaving the
            # reader to recognise the name.
            # dns-servers comes back as an array, and :find on an array finds
            # nothing -- it has to be a string before it can be searched.
            :local srv [:tostr [/ip/dns/forwarders/get [find where name=$n] dns-servers]]
            :if ([:typeof [:find $srv "192.168.255."]] = "num") do={ :set hint "  local container" }
            :if ($n = $default) do={ :set hint ($hint . "   <- suggested") }
            :if ([:len $hint] = 0) do={
                $mSay ("   " . [$mPad ($i . ")") 5] . $n)
            } else={
                $mSay ("   " . [$mPad ($i . ")") 5] . [$mPad $n 24] . $hint)
            }
            :set i ($i + 1)
        }
        :if ($showingAll = false) do={
            $mSay ("   a)   show all " . [:len $full] . " forwarders, including _noverify and _udp")
        }
        $mSay ("  number, or Enter for " . $default . ":")
        :local a [/terminal ask]
        :if ([:len $a] = 0) do={ :return $default }
        :if ($a = "a" and $showingAll = false) do={
            :set names $full
            :set showingAll true
        } else={
            :local num [:tonum $a]
            :if ([:typeof $num] = "num" and $num >= 1 and $num <= [:len $names]) do={
                :return ($names->($num - 1))
            }
            $mSay "  not a valid number"
        }
    }
}
:global mPickFwd

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
                # The chosen forwarder is appended, not substituted: the
                # companion body sets $ForwardTo as a default and the last
                # assignment wins, so the file stays readable and the choice is
                # visible as its own line at the bottom.
                :if (($m->"fwd") = true) do={
                    :local chosen [$mPickFwd list=$listName default=($m->"def")]
                    :set lbody ($lbody . "
# forwarder chosen during install, edit freely
:global ForwardTo \"" . $chosen . "\"
")
                    $mOk ($listName . " will forward to " . $chosen)
                }
                :onerror e in={
                    /system/script/add name=$listName source=$lbody comment="sros:list (yours, never overwritten)"
                    $mOk ($listName . " installed")
                } do={ $mErr $listName $e }
            }
        } else={
            $mSkip ($listName . " kept, it is yours")
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
                $mSkip ($sname . " up to date")
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
                    :if ($c = "1") do={ $mSkip ($sname . " kept, upstream ignored") }
                    :if ($c != "1" and $c != "2") do={ $mSkip ($sname . " skipped") }
                } else={
                    :if ($edited) do={
                        $mSkip ($sname . " edited locally, left alone")
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
        $mSkip "scheduler update_FWD present"
    }
    :if ([:len [/system/scheduler/find where name="route_UP"]] = 0) do={
        /system/scheduler/add name=route_UP interval=10s comment="sros:lists" on-event="/system/script/run route_UP"
        $mOk "scheduler route_UP every 10s"
    } else={
        $mSkip "scheduler route_UP present"
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
