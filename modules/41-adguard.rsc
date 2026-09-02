# scripts-ros :: modules/41-adguard.rsc
# Menu entry 41. AdGuard Home in a container -- filtering DNS with a web UI,
# an alternative to DNSProxy for people who want per-client rules and query
# logs rather than a plain parallel-upstream cache.
#
# Registry note, because RouterOS does not guess one: Docker Hub images must
# carry the host explicitly.
#   user image     registry-1.docker.io/adguard/adguardhome
#   official image registry-1.docker.io/library/alpine
# Only the projects own images live on ghcr.io.
#
# Link network 192.168.255.12/30 -- .13 is the router, .14 is the container.
# The /30 at 192.168.255.4 is intentionally left free for the next container.
#
# Two mounts are mandatory: without them the configuration and the query log
# live inside the container layer and vanish on every repull.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mContState
:global mStateGet
:global mRepull
:global mStateSet
:global mRun
:global mYesNo
:global mOk

$mHdr "AdGuard Home"

:local slot [$mStateGet "slot"]
:if ([:len $slot] = 0) do={
    $mSay "  [ !! ] no storage slot chosen yet, run row 20 first"
} else={

:local rootDir ([$mStateGet "path"] . "Containers/AdGuardHome")

:onerror e in={
    :if ([$mNeed id=[/interface/veth/find where name="AdGuardHome"] name="veth AdGuardHome"]) do={
        /interface/veth/add name=AdGuardHome address=192.168.255.14/30 gateway=192.168.255.13
        $mOk "veth AdGuardHome"
    }
    :if ([$mNeed id=[/ip/address/find where address="192.168.255.13/30"] name="address 192.168.255.13/30"]) do={
        /ip/address/add address=192.168.255.13/30 interface=AdGuardHome
        $mOk "address 192.168.255.13/30"
    }
    :foreach l in={"InAccept";"Containers"} do={
        :if ([:len [/interface/list/find where name=$l]] = 0) do={
            /interface/list/add name=$l
            $mOk ("interface-list " . $l)
        }
        :if ([$mNeed id=[/interface/list/member/find where list=$l and interface="AdGuardHome"] name=("member AdGuardHome in " . $l)]) do={
            /interface/list/member/add interface=AdGuardHome list=$l
            $mOk ("member AdGuardHome in " . $l)
        }
    }
    :if ([$mNeed id=[/ip/dns/forwarders/find where name="AdGuardHome"] name="forwarder AdGuardHome"]) do={
        /ip/dns/forwarders/add name=AdGuardHome dns-servers=192.168.255.14 verify-doh-cert=no
        $mOk "forwarder AdGuardHome"
    }
} do={ $mErr "adguard network" $e }

# Persistent state. AdGuard writes its config on first run through the web UI,
# so losing this mount means redoing the setup wizard after every update.
:local mounts {
    {"c"="AdGuardWork"; "n"="adguard_work"; "src"="/adguard_work/"; "dst"="/opt/adguardhome/work"};
    {"c"="AdGuardConf"; "n"="adguard_conf"; "src"="/adguard_conf/"; "dst"="/opt/adguardhome/conf"}
}
:onerror e in={
    :foreach m in=$mounts do={
        :if ([$mNeed id=[/container/mounts/find where list="AdGuardHome" and dst~($m->"key")] name=("mount " . ($m->"src"))]) do={
            :onerror e2 in={ /file/add name=($m->"n") type=directory } do={}
            /container/mounts/add src=($m->"src") dst=($m->"dst") list=AdGuardHome comment=($m->"c")
            $mOk ("mount " . ($m->"src"))
        }
    }
} do={ $mErr "mounts" $e }

:if ([:len [/container/find where comment="AdGuardHome"]] = 0) do={
    :onerror e in={
        /container/add remote-image="registry-1.docker.io/adguard/adguardhome" \
            interface=AdGuardHome mountlists=AdGuardHome root-dir=$rootDir \
            start-on-boot=yes comment="AdGuardHome"
        $mOk "container added, pulling image"
    } do={ $mErr "container add" $e }
} else={
    $mOk "container entry already present"
}

$mRepull name="AdGuardHome" image="registry-1.docker.io/adguard/adguardhome"     iface="AdGuardHome" envs="" mounts="AdGuardHome" cmd=""

:local waited 0
:local done false
:local repulls 0
:while ($done = false and $waited < 600) do={
    :local st [$mContState "AdGuardHome"]
    :if ($st = "absent") do={
        $mSay "  [ !! ] container entry disappeared, aborting"
        :set done true
    } else={
        :if ($st = "running") do={
            $mOk ("container running after " . $waited . "s")
            :set done true
        } else={
            :if ([:len [/container/find where comment="AdGuardHome" and download/extract failed]] > 0) do={
                :if ($repulls < 3) do={
                    :onerror e in={ /container/repull [find where comment="AdGuardHome"] } do={}
                    :set repulls ($repulls + 1)
                    $mSay ("  ... extract failed, repull " . $repulls . " of 3")
                } else={
                    $mSay "  [ !! ] extraction keeps failing, giving up after 3 repulls"
                    :set done true
                }
            } else={
                :if ($st = "stopped") do={
                    :onerror e in={ /container/start [find where comment="AdGuardHome" and stopped] } do={}
                }
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
    $mSay "  [ !! ] AdGuard Home did not reach running state within 600s"
}

$mSay ""
$mSay "  first run needs the setup wizard:  http://192.168.255.14:3000"
$mSay "  in it, set the DNS listen address to 0.0.0.0 and move the web"
$mSay "  interface off port 80, then come back here."

# Offering the resolver role is one shared decision, made in 45-resolver so the
# rules and the watchdog exist in exactly one place. Declining is fine and
# leaves /ip dns untouched.
:global mResolverCandidate "AdGuardHome"
:global mResolverAddr "192.168.255.14"
$mRun "modules/45-resolver.rsc"
}
