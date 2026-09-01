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
        :if ([$mNeed id=[/container/mounts/find where comment="MihomoProxyRoS"] name="mount /mihomo"]) do={
            :onerror e2 in={ /file/add name=mihomo type=directory } do={}
            /container/mounts/add src=/mihomo/ dst=/root/.config/mihomo/ list=MihomoProxyRoS comment="MihomoProxyRoS"
            $mOk "mount /mihomo"
        }
    } do={ $mErr "mounts" $e }
} else={
    :local small {
        {"c"="MihomoProxyRoSAWG";     "n"="awg_conf";     "src"="/awg_conf/";     "dst"="/root/.config/mihomo/awg/"};
        {"c"="MihomoProxyRoSProxies"; "n"="proxies_yaml"; "src"="/proxies_yaml/"; "dst"="/root/.config/mihomo/proxies_mount/"};
        {"c"="MihomoProxyRoSRuleSet"; "n"="ruleset_txt";  "src"="/ruleset_txt/";  "dst"="/root/.config/mihomo/rule_set_list"}
    }
    :onerror e in={
        :foreach m in=$small do={
            :if ([$mNeed id=[/container/mounts/find where comment=($m->"c")] name=("mount " . ($m->"src"))]) do={
                :onerror e2 in={ /file/add name=($m->"n") type=directory } do={}
                /container/mounts/add src=($m->"src") dst=($m->"dst") list=MihomoProxyRoS comment=($m->"c")
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
            :if ($st = "stopped") do={
                :onerror e in={ /container/start [find where comment="MihomoProxyRoS" and stopped] } do={}
            }
            :if ($waited % 30 = 0) do={ $mSay ("  ... " . $st . " (" . $waited . "s)") }
            :delay 5
            :set waited ($waited + 5)
        }
    }
}
:if ($done = false) do={
    $mSay "  [ !! ] container did not reach running state within 600s"
    $mSay "         check /log print and /container print detail"
}

}
