# scripts-ros :: install.rsc
# The only file a user pastes into the terminal. Everything else is fetched.
#
# It stays small on purpose: preflight, load the library, draw the menu, hand
# control to a module. Modules can grow; this file must not.
#
#   :global mBranch "dev"                     # test another branch
#   :global mBase "http://192.168.88.10:8000" # or a local http server
#   :global r [/tool fetch url="https://raw.githubusercontent.com/Medium1992/scripts-ros/refs/heads/main/install.rsc" mode=https output=user as-value]
#   :global s [:parse ($r->"data")] ; $s

# ================================================================ preflight
# Runs before the library exists, so it may only use plain console commands.

:local verFull [/system/resource/get version]
:local ver $verFull
:local sp [:find $ver " "]
:if ([:typeof $sp] != "nothing") do={ :set ver [:pick $ver 0 $sp] }

:local d1 [:find $ver "."]
:local major [:tonum [:pick $ver 0 $d1]]
:local rest [:pick $ver ($d1 + 1) [:len $ver]]
:local d2 [:find $rest "."]
:local minor 0
:local patch 0
:if ([:typeof $d2] = "nothing") do={
    :set minor [:tonum $rest]
} else={
    :set minor [:tonum [:pick $rest 0 $d2]]
    :set patch [:tonum [:pick $rest ($d2 + 1) [:len $rest]]]
}
:local verNum (($major * 10000) + ($minor * 100) + $patch)

:put "=============================================="
:put "  scripts-ros installer"
:put ("  RouterOS " . $verFull . " on " . [/system/resource/get architecture-name])
:put ("  " . [/system/resource/get board-name])
:put "=============================================="

:local blocked false

# 7.24.0 shipped a broken argument lookup in the console "find" command, fixed
# in 7.24.1. This project resolves nearly every object through
# "find where comment=", so 7.24.0 is not merely old, it is wrong.
:if ($verNum = 72400) do={
    :put ""
    :put "  [ !! ] RouterOS 7.24.0 has a broken console 'find' lookup."
    :put "         This installer relies on it. Upgrade to 7.24.1 or newer."
    :set blocked true
}
:if ($verNum < 72401) do={
    :put ""
    :put ("  [ !! ] RouterOS " . $ver . " is below the supported floor 7.24.1.")
    :put "         Upgrade first: /system package update check-for-updates"
    :set blocked true
}

:if ($blocked = false) do={

# ============================================================ load library
# mBase is RECOMPUTED here every run, never inherited. Globals survive in
# /system/script/environment between runs, so a stale mBase from an earlier
# session would silently point this installer at somebody's old dev server --
# which is exactly what happened once. The dev override is a separate name you
# have to set on purpose:
#     :global mDev "http://192.168.88.10:8000"
:global mBranch
:if ([:typeof $mBranch] = "nothing") do={ :set mBranch "main" }
:global mDev
:global mBase
:set mBase ("https://raw.githubusercontent.com/Medium1992/scripts-ros/refs/heads/" . $mBranch)
:if ([:typeof $mDev] != "nothing") do={
    :if ([:len $mDev] > 0) do={
        :set mBase $mDev
        :put "  [ !! ] using a local development source, not GitHub"
    }
}

# The GitHub workaround belongs in the snippet you paste, not here -- this file
# has already had to come down from GitHub to be running at all. What is left
# here only tops up the same rules for the module downloads that follow, and is
# a no-op when the snippet already added them.
:onerror e in={
    :local added 0
    :if ([:len [/ip/firewall/nat/find where comment="GitHub_Fastly_fix_dstnat"]] = 0) do={
        /ip/firewall/nat/add action=netmap chain=dstnat dst-address=185.199.108.0/22             to-addresses=185.199.109.0/24 comment="GitHub_Fastly_fix_dstnat"
        :set added ($added + 1)
    }
    :if ([:len [/ip/firewall/nat/find where comment="GitHub_Fastly_fix_output"]] = 0) do={
        /ip/firewall/nat/add action=netmap chain=output dst-address=185.199.108.0/22             to-addresses=185.199.109.0/24 comment="GitHub_Fastly_fix_output"
        :set added ($added + 1)
    }
    :foreach a in={"185.199.108.133";"185.199.109.133";"185.199.110.133";"185.199.111.133"} do={
        :local to ([:pick $a 0 ([:len $a] - 3)] . "154")
        :if ([:len [/ip/firewall/nat/find where comment="GitHub_Fastly_133_to_154_dstnat" and dst-address=$a]] = 0) do={
            /ip/firewall/nat/add action=dst-nat chain=dstnat dst-address=$a dst-port=443 protocol=tcp                 to-addresses=$to comment="GitHub_Fastly_133_to_154_dstnat"                 place-before=[/ip/firewall/nat/find where comment="GitHub_Fastly_fix_dstnat"]
            :set added ($added + 1)
        }
        :if ([:len [/ip/firewall/nat/find where comment="GitHub_Fastly_133_to_154_output" and dst-address=$a]] = 0) do={
            /ip/firewall/nat/add action=dst-nat chain=output dst-address=$a dst-port=443 protocol=tcp                 to-addresses=$to comment="GitHub_Fastly_133_to_154_output"                 place-before=[/ip/firewall/nat/find where comment="GitHub_Fastly_fix_output"]
            :set added ($added + 1)
        }
    }
    :if ($added > 0) do={ :put ("  GitHub Fastly workaround: " . $added . " nat rule(s) topped up") }
} do={
    :put ("  [ -- ] could not top up the GitHub workaround: " . $e)
}

:put ""
:put ("  source: " . $mBase)

# builtin-trust-store is scoped per service. If "fetch" is not in it, /tool
# fetch has no root certificates at all and cannot verify anything -- and the
# very next thing this script does is download code and execute it.
#
# Appended, never assigned. The stock "default" group already includes fetch
# along with ten other services, so on an untouched router this whole block is
# a no-op; assigning a list instead would quietly strip trust from everything
# not named here.
:onerror e in={
    :local ts [:tostr [/certificate/settings/get builtin-trust-store]]
    # The value is either a group keyword or a service list. "default" and
    # "all" already include fetch -- measured -- so leave them be. Only a
    # narrowed list gets fetch appended, and "untrusted" gets the stock group.
    :local act false
    :if ($ts = "default" or $ts = "all") do={ :set act false } else={
        :if ([:typeof [:find $ts "fetch"]] != "num") do={ :set act true }
    }
    :if ($act) do={
        :if ($ts = "untrusted") do={
            /certificate/settings/set builtin-trust-store=default
        } else={
            /certificate/settings/set builtin-trust-store=($ts . ",fetch")
        }
        # The new bundle is not usable immediately: a verified fetch still
        # fails for a second or two after the setting changes, then starts
        # working. Measured, not superstition.
        :delay 3
        :put ("  trust store: " . [:tostr [/certificate/settings/get builtin-trust-store]])
    }
} do={
    :put ("  [ -- ] could not extend the trust store: " . $e)
}

:put "  loading library ..."

:local libOk false
:local scheme "https"
:if ([:pick $mBase 0 5] = "http:") do={ :set scheme "http" }
:local checks {"yes";"no"}
:if ($scheme = "http") do={ :set checks {"no"} }

:foreach chk in=$checks do={
    :if ($libOk = false) do={
        :onerror e in={
            :local r [/tool fetch url=($mBase . "/lib.rsc") mode=$scheme check-certificate=$chk output=user as-value]
            :if (($r->"status") = "finished") do={
                :local fn [:parse ($r->"data")]
                $fn
                :set libOk true
                :if ($chk = "no" and $scheme = "https") do={
                    :put "  [ !! ] library downloaded WITHOUT certificate verification."
                    :put "         It is executed as code. Check what your router trusts."
                }
            }
        } do={
            :if ($chk = "no") do={ :put ("  [ !! ] cannot load lib.rsc: " . $e) }
        }
    }
}

:if ($libOk = false) do={
    :put "  [ !! ] aborting. Check DNS, routing and the GitHub Fastly workaround."
} else={

:global mSay
:global mRun
:global mFetch
:global mStateLoad
:global mVerNum
:set mVerNum $verNum

$mStateLoad

# ============================================================ status probes
# Kept in a separate file so the menu can show live state without pulling in
# every module. One fetch, one parse, redone after each action.
:global mStatus
:global mMenu

:global mReloadStatus do={
    :global mFetch
    :local body [$mFetch "status.rsc"]
    :if ([:len $body] = 0) do={ :return false }
    :onerror e in={
        :local fn [:parse $body]
        $fn
    } do={
        :put ("  [ !! ] status.rsc: " . $e)
        :return false
    }
    :return true
}

:global mReloadStatus
$mReloadStatus

# ================================================================= manifest
# One small file carrying an md5 of every updatable resource. Fetching it once
# at startup is what lets the menu show "update available" without downloading
# the scripts it would be comparing.
:global mManifest
:onerror e in={
    :local mf [$mFetch "manifest.rsc"]
    :if ([:len $mf] > 0) do={
        :local fn [:parse $mf]
        $fn
    }
} do={
    :put ("  [ -- ] manifest unavailable, update detection off: " . $e)
}

# ==================================================================== menu
# Menu keys are the module numbers themselves. Typing 41 is no harder than
# typing 5 and it removes the guesswork about which file a row runs.
# Rows are numbered by module, which is useful when reading the repository and
# useless when you are staring at a prompt. So the position is printed first
# and both are accepted: on a menu of eight rows, "4" and "30" mean the same
# thing and cannot collide, because no position ever reaches 10.
# A module can print thirty lines and the menu redraws immediately, so the
# result scrolls away before it can be read -- and the next prompt swallows a
# keystroke meant for the last one. Stop and wait.
:global mPause do={
    :put ""
    :put "  ---- press Enter to return to the menu ----"
    :local ignored [/terminal ask]
}

:global mDraw do={
    :global mMenu
    :global mPad
    :global mIndex
    :set mIndex [:toarray ""]
    :put ""
    :put "=============================================="
    :local i 1
    :foreach k,v in=$mMenu do={
        :set mIndex ($mIndex, $k)
        :put (" " . [$mPad ($i . ")") 4] . ($v->"state") . " " . [$mPad ($v->"title") 20] . ($v->"detail"))
        :set i ($i + 1)
    }
    :put ""
    :put "  a   install everything        s   status report"
    :put "  x   remove everything         q   quit"
    :put "=============================================="
}

:global mAction do={
    :global mRun
    :global mPause
    :put ""
    :put ("  " . ($item->"title") . ": " . ($item->"state") . " " . ($item->"detail"))
    :put "   1) install or repair"
    :put "   2) remove"
    :put "   3) back"
    :local c [/terminal ask]
    :if ($c = "1") do={ $mRun ("modules/" . ($item->"module")) ; $mPause ; :return true }
    :if ($c = "2") do={ $mRun ("modules/" . ($item->"remove")) ; $mPause ; :return true }
    :return false
}

:global mDraw
:global mPause
:global mAction
:global mReloadStatus

:local running true
:while ($running) do={
    $mDraw
    :put "choose a row number (or a / s / x / q):"
    :local pick [/terminal ask]

    :if ($pick = "q") do={
        :set running false
    } else={
        :if ($pick = "s") do={
            $mRun "modules/99-status.rsc"
            $mPause
        } else={
            :if ($pick = "x") do={
                $mRun "modules/90-uninstall.rsc"
                $mPause
                $mReloadStatus
            } else={
                :if ($pick = "a") do={
                    :foreach k,v in=$mMenu do={
                        $mRun ("modules/" . ($v->"module"))
                    }
                    $mPause
                    $mReloadStatus
                } else={
                    # Accept the printed position as well as the module
                    # number, so nobody has to know that row 4 is file 30.
                    :global mIndex
                    :local key $pick
                    :local num [:tonum $pick]
                    :if ([:typeof $num] = "num") do={
                        :if ($num >= 1 and $num <= [:len $mIndex]) do={
                            :set key ($mIndex->($num - 1))
                        }
                    }
                    :local item ($mMenu->$key)
                    :if ([:typeof $item] = "nothing") do={
                        :put ("  there is no row " . $pick . " -- type a number from the left column, or a/s/x/q")
                    } else={
                        :if ([$mAction item=$item]) do={ $mReloadStatus }
                    }
                }
            }
        }
    }
}

:put ""
:put "bye. globals cleaned."

}
}

# Single cleanup point for the whole run. Modules must never do this.
/system/script/environment/remove [find]
