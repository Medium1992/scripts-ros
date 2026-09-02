# scripts-ros :: modules/34-mihomo-run.rsc
# Mounts, image pull and start. This is the only module that waits on the
# network for minutes, so it reports progress rather than sitting silent.
#
# The mount layout depends on how much storage the router has. With a roomy
# disk the whole mihomo config directory is bind-mounted and the container
# keeps its state. On a small device only the three directories that must
# survive a restart are mounted, so the image can still be pulled.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mStateGet
:global mRepull
:global mContState

$mHdr "MihomoProxyRoS container"

:local path [$mStateGet "path"]
:local slot [$mStateGet "slot"]
:if ([:len $slot] = 0) do={
    $mSay "  [ !! ] no storage slot chosen yet, run menu entry 2 first"
} else={

:local rootDir ($path . "Containers/MihomoProxyRoS")
$mSay ("  root-dir: " . $rootDir)

:if ([/system/resource/get total-hdd-space] >= 120000000) do={
    :onerror e in={
        # Checked by dst, not by our comment: RouterOS refuses a second mount
        # with the same destination, and a mount made by hand or by the older
        # script carries a different comment, so a comment check misses it and
        # the add fails with an error that looks like a bug in this module.
        :if ([$mNeed id=[/container/mounts/find where list="MihomoProxyRoS" and dst~"config/mihomo"] name="mount /mihomo"]) do={
            :onerror e2 in={ /file/add name=mihomo type=directory } do={}
            /container/mounts/add src=/mihomo/ dst=/root/.config/mihomo/ list=MihomoProxyRoS comment="MihomoProxyRoS"
            $mOk "mount /mihomo"
        }
    } do={ $mErr "mounts" $e }
} else={
    # key is what identifies the destination when looking for an existing
    # mount: RouterOS stores dst without the trailing slash it accepts on add,
    # so an exact comparison never matches what it wrote.
    :local small {
        {"n"="awg_conf";     "src"="/awg_conf/";     "dst"="/root/.config/mihomo/awg/";            "key"="mihomo/awg"};
        {"n"="proxies_yaml"; "src"="/proxies_yaml/"; "dst"="/root/.config/mihomo/proxies_mount/";  "key"="proxies_mount"};
        {"n"="ruleset_txt";  "src"="/ruleset_txt/";  "dst"="/root/.config/mihomo/rule_set_list";   "key"="rule_set_list"}
    }
    :onerror e in={
        :foreach m in=$small do={
            :if ([$mNeed id=[/container/mounts/find where list="MihomoProxyRoS" and dst~($m->"key")] name=("mount " . ($m->"src"))]) do={
                :onerror e2 in={ /file/add name=($m->"n") type=directory } do={}
                /container/mounts/add src=($m->"src") dst=($m->"dst") list=MihomoProxyRoS comment="MihomoProxyRoS"
                $mOk ("mount " . ($m->"src"))
            }
        }
    } do={ $mErr "mounts" $e }
}

:if ([:len [/container/find where comment="MihomoProxyRoS"]] = 0) do={
    :onerror e in={
        /container/add remote-image="ghcr.io/medium1992/mihomo-proxy-ros" envlists=MihomoProxyRoS mountlists=MihomoProxyRoS interface=MihomoProxyRoS root-dir=$rootDir start-on-boot=yes comment="MihomoProxyRoS"
        $mOk "container added, pulling image"
    } do={ $mErr "container add" $e }
} else={
    $mOk "container entry already present"
}

# Pulling can take several minutes on a slow link. Poll rather than guess, and
# report the extraction state so a stuck pull is visible instead of silent.
$mRepull name="MihomoProxyRoS" image="ghcr.io/medium1992/mihomo-proxy-ros"     iface="MihomoProxyRoS" envs="MihomoProxyRoS" mounts="MihomoProxyRoS" cmd=""

:local waited 0
:local done false
:local repulls 0
:local attempts 0
:while ($done = false and $waited < 600) do={
    :local st [$mContState "MihomoProxyRoS"]
    :if ($st = "absent") do={
        $mSay "  [ !! ] container entry disappeared, aborting"
        :set done true
    } else={
        :if ($st = "running") do={
            $mOk ("container running after " . $waited . "s")
            :set done true
        } else={
            :if ([:len [/container/find where comment="MihomoProxyRoS" and download/extract failed]] > 0) do={
                # Only a repull clears a failed extraction; starting it again
                # never will, so stop trying to.
                :if ($repulls < 3) do={
                    :onerror e in={ /container/repull [find where comment="MihomoProxyRoS"] } do={}
                    :set repulls ($repulls + 1)
                    $mSay ("  ... extract failed, repull " . $repulls . " of 3")
                } else={
                    $mSay "  [ !! ] extraction keeps failing, giving up after 3 repulls"
                    :set done true
                }
            } else={
                :if ($st = "stopped") do={
                    :onerror e in={ /container/start [find where comment="MihomoProxyRoS" and stopped] } do={}
                    :set attempts ($attempts + 1)
                }
            }
            # A container that goes straight back to stopped after this many
            # tries is not slow, it is misconfigured -- waiting the full ten
            # minutes in silence tells nobody anything.
            :if ($done = false and $attempts >= 12) do={
                $mSay ("  [ !! ] the container returns to stopped after " . $attempts . " start attempts.")
                $mSay "         That is a configuration problem, not a slow pull. Check:"
                $mSay "         /log print where topics~container"
                $mSay "         /container print detail where comment=MihomoProxyRoS"
                $mSay "         a stale interface= or root-dir= is the usual cause."
                :set done true
            }
            :if ($done = false) do={
                :if ($waited % 30 = 0) do={ $mSay ("  ... " . $st . " (" . $waited . "s)") }
                :delay 5
                :set waited ($waited + 5)
            }
        }
    }
}
:if ($done = false) do={
    $mSay "  [ !! ] container did not reach running state within 600s"
}

}
