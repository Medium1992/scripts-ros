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
# The address is allocated at install time, not fixed: see $mNetAttach in
# lib.rsc for the bridge and the standalone ranges.
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
:global mNetAttach
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

# Standalone by default, like DNSProxy: it is a resolver, not a neighbour of
# the proxy.
:global agIP [$mNetAttach cname="AdGuardHome" default="standalone"]
:if ([:len $agIP] = 0) do={
    $mSay "  [ !! ] could not attach the container network, stopping here"
    :error "no container address"
}

:onerror e in={
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
        /ip/dns/forwarders/add name=AdGuardHome dns-servers=$agIP verify-doh-cert=no
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
$mSay "  Set it up in the browser, there is nothing to do from here:"
$mSay "    http://" . $agIP . ":3000    first run, the setup wizard"
$mSay "    http://" . $agIP . "         afterwards, the normal panel"
$mSay "  Everything -- upstreams, filters, per-client rules -- lives in that UI."

# Offering the resolver role is one shared decision, made in 45-resolver so the
# rules and the watchdog exist in exactly one place. Declining is fine and
# leaves /ip dns untouched.
:global mResolverCandidate "AdGuardHome"
:global mResolverAddr $agIP
$mRun "modules/45-resolver.rsc"
}
