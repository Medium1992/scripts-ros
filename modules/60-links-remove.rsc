# scripts-ros :: modules/60-links-remove.rsc
# Clears the proxy link and the subscription URL.
#
# Useful on its own: this is how you hand a router to someone else, or post a
# /export, without leaking the credentials embedded in a vless:// link.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Clear proxy link and subscription"

:if ([$mYesNo prompt="Clear LINK1 and SUB_LINK1?"] = false) do={
    $mOk "cancelled"
} else={
    :onerror e in={
        :foreach k in={"LINK1";"SUB_LINK1"} do={
            :local ids [/container/envs/find where key=$k and list="MihomoProxyRoS"]
            :if ([:len $ids] > 0) do={
                /container/envs/remove $ids
                $mOk ($k . " cleared")
            } else={
                $mOk ($k . " was not set")
            }
        }
    } do={ $mErr "envs" $e }

    :if ([:len [/container/find where comment="MihomoProxyRoS" and running]] > 0) do={
        $mSay ""
        $mSay "  the container is still running on the old values;"
        $mSay "  restart it to actually drop them."
    }
}
