# scripts-ros :: modules/40-dnsproxy.rsc
# Menu entry 4. A second container on its own /30, used as a DNS forwarder.
#
# The plumbing here is complete and tested. The image name is NOT hardcoded:
# script21.rsc referenced a DNSProxy container but never actually defined one
# (its $dnsproxy flag is read and never set), so there is no upstream spec to
# copy. Rather than invent an image reference that would fail at pull time, the
# module asks for it and remembers the answer in state.
#
# Link network 192.168.255.4/30 -- .5 is the router, .6 is the container.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mAsk
:global mStateGet
:global mStateSet
:global mContState

$mHdr "DNSProxy"

:local slot [$mStateGet "slot"]
:if ([:len $slot] = 0) do={
    $mSay "  [ !! ] no storage slot chosen yet, run menu entry 2 first"
} else={

:local image [$mStateGet "dnsproxy_image"]
$mSay ""
:if ([:len $image] > 0) do={
    $mSay ("  current image: " . $image)
    $mSay "  press Enter to keep, or type a different image reference:"
} else={
    $mSay "  container image reference for DNSProxy"
    $mSay "  example: ghcr.io/<owner>/<name>:<tag>"
    $mSay "  enter image:"
}
:local answer [$mAsk default=$image]
:if ([:len $answer] = 0) do={
    $mSay "  [ -- ] no image given, nothing to install"
} else={
:set image $answer
$mStateSet key="dnsproxy_image" value=$image

:onerror e in={
    :if ([$mNeed id=[/interface/veth/find where name="DNSProxy"] name="veth DNSProxy"]) do={
        /interface/veth/add name=DNSProxy address=192.168.255.6/30 gateway=192.168.255.5
        $mOk "veth DNSProxy"
    }
    :if ([$mNeed id=[/ip/address/find where address="192.168.255.5/30"] name="address 192.168.255.5/30"]) do={
        /ip/address/add address=192.168.255.5/30 interface=DNSProxy
        $mOk "address 192.168.255.5/30"
    }
    :foreach l in={"InAccept";"Containers"} do={
        :if ([:len [/interface/list/find where name=$l]] > 0) do={
            :if ([$mNeed id=[/interface/list/member/find where list=$l and interface="DNSProxy"] name=("member DNSProxy in " . $l)]) do={
                /interface/list/member/add interface=DNSProxy list=$l
                $mOk ("member DNSProxy in " . $l)
            }
        }
    }
} do={ $mErr "dnsproxy network" $e }

:onerror e in={
    :if ([$mNeed id=[/ip/dns/forwarders/find where name="DNSProxy"] name="forwarder DNSProxy"]) do={
        /ip/dns/forwarders/add name=DNSProxy dns-servers=192.168.255.6 verify-doh-cert=no
        $mOk "forwarder DNSProxy"
    }
} do={ $mErr "dnsproxy forwarder" $e }

:local rootDir ([$mStateGet "path"] . "Containers/DNSProxy")
:if ([:len [/container/find where comment="DNSProxy"]] = 0) do={
    :onerror e in={
        /container/add remote-image=$image interface=DNSProxy root-dir=$rootDir \
            envlists=DNSProxy start-on-boot=yes comment="DNSProxy"
        $mOk ("container added from " . $image)
    } do={ $mErr "container add" $e }
} else={
    $mOk "container entry already present"
}

:local waited 0
:local done false
:while ($done = false and $waited < 600) do={
    :local st [$mContState "DNSProxy"]
    :if ($st = "absent") do={
        $mSay "  [ !! ] container entry disappeared, aborting"
        :set done true
    } else={
        :if ($st = "running") do={
            $mOk ("container running after " . $waited . "s")
            :set done true
        } else={
            :if ($st = "stopped") do={
                :onerror e in={ /container/start [find where comment="DNSProxy" and stopped] } do={}
            }
            :if ($waited % 30 = 0) do={ $mSay ("  ... " . $st . " (" . $waited . "s)") }
            :delay 5
            :set waited ($waited + 5)
        }
    }
}
:if ($done = false) do={
    $mSay "  [ !! ] DNSProxy did not reach running state within 600s"
}

$mSay ""
$mSay "  point domains at it with:"
$mSay "  /ip/dns/static/add name=<domain> type=FWD forward-to=DNSProxy match-subdomain=yes"

}
}
