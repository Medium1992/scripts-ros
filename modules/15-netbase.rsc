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

# Telling someone to open another window and type an interface name is not
# help, it is a homework assignment. Show what the router actually has, say
# which one looks like the answer, and take a number.
:global mPickIfaces do={
    :global mSay
    :global mPad
    :local names [:toarray ""]
    :local hints [:toarray ""]

    :foreach i in=[/interface/find where !disabled] do={
        :local n [/interface/get $i name]
        # Skip our own container veths and anything already in this list.
        :local skip false
        :local t [/interface/get $i type]
        # Loopback is never an uplink or a client network, and a wifi radio is
        # normally inside the bridge rather than a list member of its own.
        :if ($t = "loopback") do={ :set skip true }
        :if ([:len [/interface/bridge/port/find where interface=$n]] > 0) do={ :set skip true }
        :if ([:len [/interface/veth/find where name=$n]] > 0) do={ :set skip true }
        :if ([:len [/interface/list/member/find where list=$list and interface=$n]] > 0) do={ :set skip true }
        :if ($skip = false) do={
            :local h [/interface/get $i type]
            :if ([/interface/get $i running] = true) do={ :set h ($h . ", running") } else={ :set h ($h . ", down") }
            # A DHCP client or a default route through it means WAN; a bridge
            # holding an address means LAN. Say so instead of making them guess.
            :if ([:len [/ip/dhcp-client/find where interface=$n]] > 0) do={ :set h ($h . ", dhcp client") }
            :if ([:len [/ip/address/find where interface=$n]] > 0) do={ :set h ($h . ", has address") }
            :set names ($names, $n)
            :set hints ($hints, $h)
        }
    }

    :if ([:len $names] = 0) do={
        $mSay "  no candidate interfaces found"
        :return 0
    }

    :while (true) do={
        $mSay ""
        $mSay ("  interfaces available for " . $list . ":")
        :local i 1
        :foreach n in=$names do={
            $mSay ("   " . [$mPad ($i . ")") 5] . [$mPad $n 16] . ($hints->($i - 1)))
            :set i ($i + 1)
        }
        $mSay ("  numbers for " . $list . ", comma separated (e.g. 1 or 1,3), or Enter to skip:")
        :local answer [/terminal ask]
        :if ([:len $answer] = 0) do={ :return 0 }

        :local picked [:toarray ""]
        :local bad false
        :foreach part in=[:toarray $answer] do={
            :local num [:tonum $part]
            :if ([:typeof $num] = "num" and $num >= 1 and $num <= [:len $names]) do={
                :set picked ($picked, ($names->($num - 1)))
            } else={
                :set bad true
            }
        }
        :if ($bad or [:len $picked] = 0) do={
            $mSay "  that is not a valid number from the list"
        } else={
            :local added 0
            :foreach n in=$picked do={
                :onerror e in={
                    /interface/list/member/add list=$list interface=$n
                    $mSay ("  [ ++ ] " . $n . " added to " . $list)
                    :set added ($added + 1)
                } do={ $mSay ("  [ !! ] " . $n . ": " . $e) }
            }
            :return $added
        }
    }
}
:global mPickIfaces

:foreach l in={"WAN";"LAN"} do={
    :local have [:len [/interface/list/member/find where list=$l]]
    :if ($have > 0) do={
        $mOk ($l . ": " . $have . " member(s)")
    } else={
        $mSay ""
        $mSay ("  [ !! ] interface list " . $l . " is empty.")
        :if ($l = "WAN") do={
            $mSay "         WAN is the uplink -- the one facing the provider."
        } else={
            $mSay "         LAN is where your clients are, usually the bridge."
        }
        :local n [$mPickIfaces list=$l]
        :if ($n = 0) do={
            $mSay ("  [ !! ] " . $l . " left empty; rules that depend on it will not match.")
        }
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
