# scripts-ros :: modules/99-status.rsc
# Menu entry s. The long form of what the menu shows in one line each.
#
# Read-only. Safe to run at any time, and the first thing to ask for when
# something is not working.

:global mHdr
:global mSay
:global mHash
:global mStateGet
:global mManifest
:global mContState

:global mShow do={
    :put ("  " . $label . [:pick "........................" 0 (24 - [:len $label])] . " " . $value)
}
:global mShow

$mHdr "System"
$mShow label="RouterOS" value=[/system/resource/get version]
$mShow label="board" value=[/system/resource/get board-name]
$mShow label="architecture" value=[/system/resource/get architecture-name]
$mShow label="uptime" value=[/system/resource/get uptime]
$mShow label="free RAM MiB" value=([/system/resource/get free-memory] / 1048576)
$mShow label="free flash MiB" value=([/system/resource/get free-hdd-space] / 1048576)
$mShow label="clock" value=([/system/clock/get date] . " " . [/system/clock/get time])
$mShow label="ntp status" value=[/system/ntp/client/get status]

$mHdr "Storage"
$mShow label="chosen slot" value=[$mStateGet "slot"]
$mShow label="container path" value=[$mStateGet "path"]
$mShow label="filesystem" value=[$mStateGet "fs"]
:foreach d in=[/disk/find] do={
    $mShow label=("disk " . [/disk/get $d slot]) value=([/disk/get $d fs] . ", " . ([/disk/get $d free] / 1048576) . " MiB free")
}
$mShow label="repull job" value=[:len [/system/scheduler/find where name="MihomoProxyRoS_repull"]]

$mHdr "DNS"
$mShow label="forwarders" value=[:len [/ip/dns/forwarders/find]]
$mShow label="allow-remote" value=[/ip/dns/get allow-remote-requests]
$mShow label="static entries" value=[:len [/ip/dns/static/find]]
$mShow label="cache used KiB" value=[/ip/dns/get cache-used]
$mShow label="servers" value=[/ip/dns/get servers]
$mShow label="doh server" value=[/ip/dns/get use-doh-server]
:local owner [$mStateGet "resolver"]
:if ([:len $owner] = 0) do={
    $mShow label="resolver owner" value="none (direct)"
} else={
    $mShow label="resolver owner" value=($owner . " at " . [$mStateGet "resolver_addr"])
}
$mShow label="watchdog DNSchange" value=[:len [/system/scheduler/find where name="DNSchange"]]

$mHdr "Firewall and routing"
$mShow label="mangle rules" value=[:len [/ip/firewall/mangle/find]]
$mShow label="address-list total" value=[:len [/ip/firewall/address-list/find]]
$mShow label="list MihomoProxyRoS" value=[:len [/ip/firewall/address-list/find where list="MihomoProxyRoS"]]
$mShow label="proxy routes" value=[:len [/ip/route/find where routing-table="MihomoProxyRoS"]]
$mShow label="disabled routes" value=[:len [/ip/route/find where disabled=yes]]
:foreach l in={"WAN";"LAN";"InAccept";"Containers"} do={
    $mShow label=("list " . $l) value=([:len [/interface/list/member/find where list=$l]] . " member(s)")
}

$mHdr "Containers"
:if ([:len [/container/find]] = 0) do={
    $mSay "  none"
} else={
    :foreach c in=[/container/find] do={
        :local cm [/container/get $c comment]
        :if ([:len $cm] = 0) do={ :set cm [/container/get $c tag] }
        :local st "stopped"
        :if ([/container/get $c running] = true) do={ :set st "running" }
        $mShow label=$cm value=($st . ", " . [/container/get $c root-dir])
    }
}
$mShow label="mihomo envs" value=[:len [/container/envs/find where list="MihomoProxyRoS"]]

$mHdr "Managed scripts"
:foreach n in={"FWD_update";"FWD_update_RU";"IP_MihomoProxyRoS";"route_UP"} do={
    :if ([:len [/system/script/find where name=$n]] = 0) do={
        $mShow label=$n value="not installed"
    } else={
        :local hLocal [$mHash [/system/script/get [find where name=$n] source]]
        :local hBase [$mStateGet ("h_" . $n)]
        :local note "ok"
        :if ([:len $hBase] = 0) do={
            :set note "installed outside this tool"
        } else={
            :if ($hLocal != $hBase) do={ :set note "EDITED LOCALLY" }
        }
        # An upstream change is visible without any fetch: the manifest loaded
        # at startup carries the current engine hash.
        :if ([:typeof $mManifest] != "nothing") do={
            :local eBase [$mStateGet ("e_" . $n)]
            :local eUp ($mManifest->"lists/engine.rsc")
            :if ($n = "route_UP") do={ :set eUp ($mManifest->"lists/route_UP.rsc") }
            :if ([:len $eBase] > 0 and [:typeof $eUp] != "nothing") do={
                :if ($eBase != $eUp) do={ :set note ($note . ", UPDATE AVAILABLE") }
            }
        }
        $mShow label=$n value=$note
    }
}
$mShow label="scheduler update_FWD" value=[:len [/system/scheduler/find where name="update_FWD"]]
$mShow label="scheduler route_UP" value=[:len [/system/scheduler/find where name="route_UP"]]

$mHdr "Recent errors"
:local errs [/log/find where topics~"error" or message~"sros"]
:if ([:len $errs] = 0) do={
    $mSay "  none"
} else={
    :local shown 0
    :foreach l in=$errs do={
        :if ($shown < 10) do={
            $mSay ("  " . [/log/get $l time] . " " . [/log/get $l message])
            :set shown ($shown + 1)
        }
    }
}
