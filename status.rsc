# scripts-ros :: status.rsc
# Builds $mMenu -- the menu rows plus the live state of each area. Fetched by
# install.rsc at start and again after every action, so the operator always
# sees what the router actually looks like, not what it looked like on entry.
#
# Every probe here must be cheap and read-only. Titles are kept under 20
# characters because :len counts bytes and the menu pads to a fixed column.
#
# state markers:  [ ok ] done   [ ~~ ] partial   [ -- ] absent   [upd ] stale

:global mMenu
:global mStateGet
:global mHash

:global mMark do={
    :if ($have = 0) do={ :return "[ -- ]" }
    :if ($have < $want) do={ :return "[ ~~ ]" }
    :return "[ ok ]"
}
:global mMark

# ------------------------------------------------------------- 1. base setup
:local dnsFwd [:len [/ip/dns/forwarders/find]]
:local dnsRemote [/ip/dns/get allow-remote-requests]
:local ntpOn [/system/ntp/client/get enabled]
:local ntpSync ([/system/ntp/client/get status] = "synchronized")
:local v6Off [/ipv6/settings/get disable-ipv6]
:local wanList [:len [/interface/list/find where name="WAN"]]
:local lanList [:len [/interface/list/find where name="LAN"]]
:local blackhole [:len [/ip/route/find where comment="BlackHole"]]

:local baseHave 0
:if ($dnsFwd >= 12 and $dnsRemote) do={ :set baseHave ($baseHave + 1) }
:if ($ntpOn) do={ :set baseHave ($baseHave + 1) }
:if ($v6Off) do={ :set baseHave ($baseHave + 1) }
:if ($wanList > 0 and $lanList > 0) do={ :set baseHave ($baseHave + 1) }
:if ($blackhole >= 3) do={ :set baseHave ($baseHave + 1) }
:local caCount [:len [/certificate/find where name~"^cacert.pem"]]

:local baseDetail ("dns " . $dnsFwd . " fwd")
:if ($ntpOn) do={
    :if ($ntpSync) do={
        :set baseDetail ($baseDetail . ", ntp synced")
    } else={
        :set baseDetail ($baseDetail . ", ntp NOT synced")
    }
} else={
    :set baseDetail ($baseDetail . ", ntp off")
}
:if ($v6Off) do={
    :set baseDetail ($baseDetail . ", ipv6 off")
} else={
    :set baseDetail ($baseDetail . ", ipv6 ON")
}
:if ($caCount > 0) do={ :set baseDetail ($baseDetail . ", " . $caCount . " roots") }

# ---------------------------------------------------------------- 2. storage
:local slot [$mStateGet "slot"]
:local storHave 0
:local storDetail "no slot chosen"
:if ([:len $slot] > 0) do={
    :set storHave 2
    :if ($slot = "system") do={
        :set storDetail ("system, " . ([/system/resource/get free-hdd-space] / 1048576) . " MiB free")
    } else={
        :local d [/disk/find where slot=$slot]
        :if ([:len $d] = 0) do={
            :set storHave 1
            :set storDetail ($slot . " MISSING")
        } else={
            :local fs [/disk/get $d fs]
            :set storDetail ($slot . " " . $fs . ", " . ([/disk/get $d free] / 1048576) . " MiB free")
            :if ($fs = "tmpfs") do={
                :if ([:len [/system/scheduler/find where name="MihomoProxyRoS_repull"]] = 0) do={
                    :set storHave 1
                    :set storDetail ($storDetail . ", NO repull")
                } else={
                    :set storDetail ($storDetail . ", repull ok")
                }
            }
        }
    }
}

# --------------------------------------------------------- 3. MihomoProxyRoS
:local mhCont [:len [/container/find where comment="MihomoProxyRoS"]]
:local mhRun [:len [/container/find where comment="MihomoProxyRoS" and running]]
:local mhVeth [:len [/interface/veth/find where name="MihomoProxyRoS"]]
:local mhTable [:len [/routing/table/find where comment="MihomoProxyRoS"]]
:local mhMangle [:len [/ip/firewall/mangle/find where comment~"Mihomo" or comment~"Accept_no_mark"]]
:local mhEnv [:len [/container/envs/find where list="MihomoProxyRoS"]]

:local mhHave 0
:if ($mhVeth > 0) do={ :set mhHave ($mhHave + 1) }
:if ($mhTable > 0) do={ :set mhHave ($mhHave + 1) }
:if ($mhMangle >= 5) do={ :set mhHave ($mhHave + 1) }
:if ($mhEnv >= 10) do={ :set mhHave ($mhHave + 1) }
:if ($mhRun > 0) do={ :set mhHave ($mhHave + 1) }

:local mhMode [$mStateGet "mihomo_mode"]
:if ([:len $mhMode] = 0) do={ :set mhMode "?" }

# In container-only mode the mangle rules are absent by design, so counting
# them as missing would show a permanent [ ~~ ] on a correct install.
:if ($mhMode = "container") do={
    :set mhHave 0
    :if ($mhVeth > 0) do={ :set mhHave ($mhHave + 2) }
    :if ($mhEnv >= 10) do={ :set mhHave ($mhHave + 2) }
    :if ($mhRun > 0) do={ :set mhHave ($mhHave + 1) }
}

:local mhDetail ""
:if ($mhCont = 0) do={
    :set mhDetail ($mhMode . ", not pulled, " . $mhEnv . " envs")
} else={
    :if ($mhRun > 0) do={
        :set mhDetail ($mhMode . ", running, " . $mhEnv . " envs")
    } else={
        :set mhDetail ($mhMode . ", STOPPED, " . $mhEnv . " envs")
    }
}

# --------------------------------------------------------------- 4. DNSProxy
:local owner [$mStateGet "resolver"]

:local dpCont [:len [/container/find where comment="DNSProxy"]]
:local dpRun [:len [/container/find where comment="DNSProxy" and running]]
:local dpHave 0
:local dpDetail "not installed"
:if ($dpCont > 0) do={
    :set dpHave 1
    :set dpDetail "installed, STOPPED"
    :if ($dpRun > 0) do={
        :set dpHave 2
        :set dpDetail "running"
    }
    :if ($owner = "DNSProxy") do={
        :set dpDetail ($dpDetail . ", RESOLVER")
    }
}

# ------------------------------------------------------------ 5. list scripts
:local lsNames {"FWD_update";"FWD_update_RU";"IP_MihomoProxyRoS";"route_UP"}
:local lsHave 0
:local lsStale 0
:local lsEdited 0
:foreach n in=$lsNames do={
    :if ([:len [/system/script/find where name=$n]] > 0) do={
        :set lsHave ($lsHave + 1)
        :local base [$mStateGet ("h_" . $n)]
        :local up [$mStateGet ("u_" . $n)]
        :local cur [$mHash [/system/script/get [find where name=$n] source]]
        :if ([:len $base] > 0 and $cur != $base) do={ :set lsEdited ($lsEdited + 1) }
        :if ([:len $up] > 0 and $up != $base) do={ :set lsStale ($lsStale + 1) }
    }
}
:local lsDetail ($lsHave . " of " . [:len $lsNames] . " installed")
:if ($lsEdited > 0) do={ :set lsDetail ($lsDetail . ", " . $lsEdited . " edited") }
:if ($lsStale > 0) do={ :set lsDetail ($lsDetail . ", " . $lsStale . " UPDATE") }
:if ([:len [/system/scheduler/find where name="update_FWD"]] = 0 and $lsHave > 0) do={
    :set lsDetail ($lsDetail . ", no schedule")
}

# ------------------------------------------------------------- 6. links / sub
:local lnLink ""
:local lnSub ""
:onerror e in={ :set lnLink [/container/envs/get [find where key="LINK1" and list="MihomoProxyRoS"] value] } do={}
:onerror e in={ :set lnSub [/container/envs/get [find where key="SUB_LINK1" and list="MihomoProxyRoS"] value] } do={}
:local lnHave 0
:local lnDetail "no link, no subscription"
:if ([:len $lnLink] > 1) do={ :set lnHave ($lnHave + 1) }
:if ([:len $lnSub] > 1) do={ :set lnHave ($lnHave + 1) }
:if ($lnHave > 0) do={
    :if ([:len $lnLink] > 1) do={
        :set lnDetail ("LINK1 " . [:pick $lnLink 0 10] . "...")
    } else={
        :set lnDetail "LINK1 empty"
    }
    :if ([:len $lnSub] > 1) do={ :set lnDetail ($lnDetail . ", SUB set") }
}

# --------------------------------------------------------------- 41. AdGuard
:local agCont [:len [/container/find where comment="AdGuardHome"]]
:local agRun [:len [/container/find where comment="AdGuardHome" and running]]
:local agHave 0
:local agDetail "not installed"
:if ($agCont > 0) do={
    :set agHave 1
    :set agDetail "installed, STOPPED"
    :if ($agRun > 0) do={
        :set agHave 2
        :set agDetail "running, UI on :3000"
    }
    :if ($owner = "AdGuardHome") do={
        :set agDetail ($agDetail . ", RESOLVER")
    }
}

# --------------------------------------------------------------- build menu
:set mMenu {
    "10"={"module"="10-base.rsc";     "remove"="10-base-remove.rsc";     "title"="Base settings"};
    "20"={"module"="20-storage.rsc";  "remove"="20-storage-remove.rsc";  "title"="Container storage"};
    "30"={"module"="30-mihomo.rsc";   "remove"="30-mihomo-remove.rsc";   "title"="MihomoProxyRoS"};
    "40"={"module"="40-dnsproxy.rsc"; "remove"="40-dnsproxy-remove.rsc"; "title"="DNSProxy"};
    "41"={"module"="41-adguard.rsc";  "remove"="41-adguard-remove.rsc";  "title"="AdGuard Home"};
    "50"={"module"="50-lists.rsc";    "remove"="50-lists-remove.rsc";    "title"="Resource lists"};
    "60"={"module"="60-links.rsc";    "remove"="60-links-remove.rsc";    "title"="Proxy link / sub"}
}


:set ($mMenu->"10"->"state")  [$mMark have=$baseHave want=5]
:set ($mMenu->"10"->"detail") $baseDetail
:set ($mMenu->"20"->"state")  [$mMark have=$storHave want=2]
:set ($mMenu->"20"->"detail") $storDetail
:set ($mMenu->"30"->"state")  [$mMark have=$mhHave want=5]
:set ($mMenu->"30"->"detail") $mhDetail
:set ($mMenu->"40"->"state")  [$mMark have=$dpHave want=2]
:set ($mMenu->"40"->"detail") $dpDetail
:set ($mMenu->"41"->"state")  [$mMark have=$agHave want=2]
:set ($mMenu->"41"->"detail") $agDetail
:set ($mMenu->"50"->"state")  [$mMark have=$lsHave want=4]
:if ($lsStale > 0) do={ :set ($mMenu->"50"->"state") "[upd ]" }
:set ($mMenu->"50"->"detail") $lsDetail
:set ($mMenu->"60"->"state")  [$mMark have=$lnHave want=2]
:set ($mMenu->"60"->"detail") $lnDetail
