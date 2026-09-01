# scripts-ros :: modules/60-links.rsc
# Creates the proxy link and subscription templates.
#
# It does NOT ask for a vless:// link. Typing one into a RouterOS terminal is
# unpleasant and error-prone -- they are long, they contain characters the
# console is picky about, and a typo is invisible. What it does instead is put
# two empty, disabled entries in place:
#
#   LINK0      disabled  template for LINK1, LINK2, ...
#   SUB_LINK0  disabled  template for SUB_LINK1, ...
#
# Disabled means mihomo never reads them, so they sit there harmlessly as a
# reminder of the exact key names. Fill one in and enable it -- in Winbox,
# where pasting a link actually works -- or set the real key from the console
# with the command printed below.
#
# Numbering starts at 1 for live entries; 0 is deliberately outside that range.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mNeed

$mHdr "Proxy link and subscription"

:onerror e in={
    :foreach k in={"LINK0";"SUB_LINK0"} do={
        :if ([$mNeed id=[/container/envs/find where key=$k and list="MihomoProxyRoS"] name=("template " . $k)]) do={
            /container/envs/add key=$k list=MihomoProxyRoS value="" disabled=yes
            $mOk ("template " . $k . " (empty, disabled)")
        }
    }
} do={ $mErr "templates" $e }

# Report what is actually configured, so it is clear whether anything is set.
:local live 0
:foreach k in={"LINK1";"SUB_LINK1"} do={
    :local ids [/container/envs/find where key=$k and list="MihomoProxyRoS" and !disabled]
    :if ([:len $ids] > 0) do={
        :local v [/container/envs/get $ids value]
        :if ([:len $v] > 1) do={
            $mOk ($k . " is set: " . [:pick $v 0 24] . "...")
            :set live ($live + 1)
        }
    }
}

$mSay ""
:if ($live = 0) do={
    $mSay "  no proxy link configured yet. Either enable LINK0 and paste your"
    $mSay "  link into it in Winbox, or set the real key from here:"
} else={
    $mSay "  to change it later:"
}
# Printed without quotes on purpose: escaped quotes inside a string are a
# parse hazard here, and RouterOS accepts these values unquoted anyway.
$mSay "  /container/envs/add key=LINK1 list=MihomoProxyRoS value=vless://..."
$mSay "  /container/envs/set [find where key=LINK1 and list=MihomoProxyRoS] value=vless://..."
$mSay "  supported: vless:// vmess:// ss:// trojan://  and SUB_LINK1 for a subscription URL"

:if ([:len [/container/find where comment="MihomoProxyRoS" and running]] > 0) do={
    $mSay ""
    $mSay "  the container is running with the values it started with;"
    $mSay "  restart it after changing them."
}
