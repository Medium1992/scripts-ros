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

# raw.githubusercontent.com resolves onto Fastly ranges that are commonly
# throttled here, and the very next thing this script does is download from
# there. 15-netbase installs these too, but that runs long after the first
# fetch has already had to succeed -- so they belong in preflight, before it.
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
    :if ($added > 0) do={ :put ("  GitHub Fastly workaround: " . $added . " nat rule(s) added") }
} do={
    :put ("  [ -- ] could not add the GitHub workaround: " . $e)
}

:put ""
:put ("  source: " . $mBase)

# builtin-trust-store is scoped per service. If "fetch" is not in it, /tool
# fetch has no root certificates at all and cannot verify anything -- and the
# very next thing this script does is download code and execute it. Add it
# before that happens, preserving whatever is already there.
:onerror e in={
    :local ts [/certificate/settings/get builtin-trust-store]
    # A failed :find reports typeof "nil", not "nothing" -- "nothing" is for
    # variables that were never set. Comparing against the wrong one here
    # silently means "already present" and skips the fix.
    :if ([:typeof [:find $ts "fetch"]] != "num") do={
        :if ([:len $ts] = 0 or $ts = "none") do={
            /certificate/settings/set builtin-trust-store=fetch
        } else={
            /certificate/settings/set builtin-trust-store=($ts . ",fetch")
        }
        # The new bundle is not usable immediately: a verified fetch still
        # fails for a second or two after the setting changes, then starts
        # working. Measured, not superstition.
        :delay 3
        :put ("  trust store: " . [/certificate/settings/get builtin-trust-store])
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
:global mDraw do={
    :global mMenu
    :put ""
    :put "=============================================="
    :foreach k,v in=$mMenu do={
        :global mPad
        :put (" " . [$mPad $k 3] . ($v->"state") . " " . [$mPad ($v->"title") 21] . ($v->"detail"))
    }
    :put ""
    :put "  a   [    ] install everything"
    :put "  s   [    ] full status report"
    :put "  x   [    ] remove everything"
    :put "  q   [    ] quit"
    :put "=============================================="
}

# Picking a row asks what to do with it. Install and remove are the same
# choice at the same place, so removing one piece never means hunting for a
# separate uninstall flow -- and never means removing more than that piece.
:global mAction do={
    :global mRun
    :put ""
    :put ("  " . ($item->"title") . ": " . ($item->"state") . " " . ($item->"detail"))
    :put "   1) install or repair"
    :put "   2) remove"
    :put "   3) back"
    :local c [/terminal ask]
    :if ($c = "1") do={ $mRun ("modules/" . ($item->"module")) ; :return true }
    :if ($c = "2") do={ $mRun ("modules/" . ($item->"remove")) ; :return true }
    :return false
}

:global mDraw
:global mAction
:global mReloadStatus

:local running true
:while ($running) do={
    $mDraw
    :put "select:"
    :local pick [/terminal ask]

    :if ($pick = "q") do={
        :set running false
    } else={
        :if ($pick = "s") do={
            $mRun "modules/99-status.rsc"
        } else={
            :if ($pick = "x") do={
                $mRun "modules/90-uninstall.rsc"
                $mReloadStatus
            } else={
                :if ($pick = "a") do={
                    :foreach k,v in=$mMenu do={
                        $mRun ("modules/" . ($v->"module"))
                    }
                    $mReloadStatus
                } else={
                    :local item ($mMenu->$pick)
                    :if ([:typeof $item] = "nothing") do={
                        :put "  unknown choice"
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
