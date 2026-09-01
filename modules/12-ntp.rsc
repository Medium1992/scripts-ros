# scripts-ros :: modules/12-ntp.rsc
# Clock. Everything TLS depends on it, so this runs early and the caller waits
# for the first sync before pulling anything over https.

:global mHdr
:global mOk
:global mSay
:global mNeed
:global mSkip
:global mErr

$mHdr "NTP"

:local servers {"0.ru.pool.ntp.org";"1.ru.pool.ntp.org";"2.ru.pool.ntp.org";"3.ru.pool.ntp.org"}

:onerror e in={
    :if ([/system/ntp/client/get enabled] = true) do={
        $mSkip "ntp client already enabled"
    } else={
        /system/ntp/client/set enabled=yes
        $mOk "ntp client enabled"
    }
    :local made 0
    :local kept 0
    :foreach srv in=$servers do={
        :if ([:len [/system/ntp/client/servers/find where address=$srv]] = 0) do={
            /system/ntp/client/servers/add address=$srv
            :set made ($made + 1)
        } else={ :set kept ($kept + 1) }
    }
    :if ($made > 0) do={
        $mOk ($made . " ntp server(s) added, " . $kept . " already present")
    } else={
        $mSkip ("all " . $kept . " ntp servers already present")
    }
} do={ $mErr "ntp" $e }

# Wait for the first sync rather than sleeping a fixed 10s and hoping.
:onerror e in={
    :local waited 0
    :while ([/system/ntp/client/get status] != "synchronized" and $waited < 30) do={
        :delay 2
        :set waited ($waited + 2)
    }
    :if ([/system/ntp/client/get status] = "synchronized") do={
        $mSay ("  [ ok ] clock synced after " . $waited . "s: " . [/system/clock/get date] . " " . [/system/clock/get time])
    } else={
        $mSay "  [ !! ] clock not synced after 30s, https may fail on cert validity"
    }
} do={ $mErr "ntp wait" $e }
