# scripts-ros :: modules/60-links.rsc
# Menu entry 6. The proxy link and the subscription URL.
#
# Split out from the environment module on purpose: changing a subscription is
# the single most frequent reason to come back to this installer, and it should
# not require touching anything else. Re-run this alone, restart the container,
# done.
#
# Interactive: needs a real terminal, never run it from a scheduler.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mAsk

$mHdr "Proxy link and subscription"

# key | prompt | what a valid value looks like
:local fields {
    {"k"="LINK1";     "p"="proxy link";  "hint"="vless:// vmess:// ss:// trojan://"};
    {"k"="SUB_LINK1"; "p"="subscription"; "hint"="http:// or https:// URL"}
}

:foreach f in=$fields do={
    :local key ($f->"k")
    :local cur ""
    :onerror e in={
        :set cur [/container/envs/get [find where key=$key and list="MihomoProxyRoS"] value]
    } do={ :set cur "" }

    $mSay ""
    :if ([:len $cur] > 1) do={
        $mSay ("  current " . $key . ": " . [:pick $cur 0 32] . "...")
    } else={
        $mSay ("  current " . $key . ": (empty)")
    }
    $mSay ("  enter " . ($f->"p") . " (" . ($f->"hint") . "), or Enter to keep:")

    :local input [$mAsk default=""]
    :if ([:len $input] = 0) do={
        $mOk ($key . " unchanged")
    } else={
        :onerror e in={
            :if ([:len [/container/envs/find where key=$key and list="MihomoProxyRoS"]] = 0) do={
                /container/envs/add key=$key list=MihomoProxyRoS value=$input
                $mOk ($key . " set")
            } else={
                /container/envs/set [find where key=$key and list="MihomoProxyRoS"] value=$input
                $mOk ($key . " updated")
            }
        } do={ $mErr $key $e }
    }
}

# An env change only reaches mihomo through a restart, and forgetting that is
# the classic "I changed the link and nothing happened".
:if ([:len [/container/find where comment="MihomoProxyRoS" and running]] > 0) do={
    $mSay ""
    $mSay "  container is running with the old values."
    $mSay "  restart it to apply: /container/stop [find where comment=\"MihomoProxyRoS\"]"
    $mSay "                       /container/start [find where comment=\"MihomoProxyRoS\"]"
}
