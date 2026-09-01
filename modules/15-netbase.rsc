# scripts-ros :: modules/15-netbase.rsc
# Interface lists, blackhole routes, the fasttrack correction and the GitHub
# Fastly workaround. Everything the later modules assume already exists.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mErr
:global mAsk

$mHdr "Network base"

# WAN and LAN drive every mangle rule later. If they are empty the proxy will
# appear to install cleanly and then route nothing, so stop and say so.
:onerror e in={
    :foreach l in={"WAN";"LAN"} do={
        :if ([$mNeed id=[/interface/list/find where name=$l] name=("interface-list " . $l)]) do={
            /interface/list/add name=$l
            $mOk ("interface-list " . $l)
        }
    }
} do={ $mErr "interface lists" $e }

:foreach l in={"WAN";"LAN"} do={
    :if ([:len [/interface/list/member/find where list=$l]] = 0) do={
        $mSay ("  [ !! ] interface list " . $l . " has no members.")
        $mSay ("         Add them now in another window, then press Enter:")
        $mSay ("         /interface/list/member/add list=" . $l . " interface=<name>")
        :local ignored [$mAsk default=""]
        :if ([:len [/interface/list/member/find where list=$l]] = 0) do={
            $mSay ("  [ !! ] " . $l . " still empty, later modules will not route correctly")
        } else={
            $mOk ($l . " now has " . [:len [/interface/list/member/find where list=$l]] . " member(s)")
        }
    } else={
        $mOk ($l . ": " . [:len [/interface/list/member/find where list=$l]] . " member(s)")
    }
}

# RFC1918 blackholes stop a default route from leaking private destinations out
# of the WAN when the proxy table is not the one being consulted.
:local privates {"10.0.0.0/8";"172.16.0.0/12";"192.168.0.0/16"}
:onerror e in={
    :foreach p in=$privates do={
        :if ([$mNeed id=[/ip/route/find where dst-address=$p and comment="BlackHole" and routing-table="main"] name=("blackhole " . $p)]) do={
            /ip/route/add blackhole comment=BlackHole distance=254 dst-address=$p gateway="" routing-table=main
            $mOk ("blackhole " . $p)
        }
    }
} do={ $mErr "blackhole routes" $e }

# Fasttracked connections skip mangle, so a fasttrack rule that matches marked
# traffic quietly disables the whole proxy path for those flows.
:onerror e in={
    :local ft [/ip/firewall/filter/find where action=fasttrack-connection]
    :if ([:len $ft] > 0) do={
        /ip/firewall/filter/set $ft connection-mark=no-mark
        $mOk ("fasttrack limited to no-mark (" . [:len $ft] . " rule(s))")
    } else={
        $mOk "no fasttrack rules present"
    }
} do={ $mErr "fasttrack" $e }

# raw.githubusercontent.com resolves onto Fastly ranges that are commonly
# throttled; remapping them keeps every later fetch in this project alive.
:onerror e in={
    :if ([$mNeed id=[/ip/firewall/nat/find where comment="GitHub_Fastly_fix_dstnat"] name="nat GitHub Fastly dstnat"]) do={
        /ip/firewall/nat/add action=netmap chain=dstnat dst-address=185.199.108.0/22 \
            to-addresses=185.199.109.0/24 comment="GitHub_Fastly_fix_dstnat"
        $mOk "nat GitHub Fastly dstnat"
    }
    :if ([$mNeed id=[/ip/firewall/nat/find where comment="GitHub_Fastly_fix_output"] name="nat GitHub Fastly output"]) do={
        /ip/firewall/nat/add action=netmap chain=output dst-address=185.199.108.0/22 \
            to-addresses=185.199.109.0/24 comment="GitHub_Fastly_fix_output"
        $mOk "nat GitHub Fastly output"
    }
} do={ $mErr "github fastly nat" $e }
