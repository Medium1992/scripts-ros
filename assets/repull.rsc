# scripts-ros :: assets/repull.rsc
# Installed as the system script MihomoProxyRoS_repull and run at startup when
# the container lives on a tmpfs slot.
#
# A RAM disk is empty after a reboot, so the container entry survives while its
# root-dir does not. Removing the orphan and pulling again is the only way back
# to a running container. It reads its path from sros_state rather than having
# one baked in, so moving the container to another slot needs no edit here.

:global mS
:onerror e in={
    :local fn [:parse [/system/script/get [find where name="sros_state"] source]]
    $fn
} do={
    :log error "MihomoProxyRoS_repull: cannot read sros_state, aborting"
    :error "no state"
}

:local rootDir (($mS->"path") . "Containers/MihomoProxyRoS")

:local c [/container/find where comment="MihomoProxyRoS"]
:if ([:len $c] > 0) do={
    :onerror e in={ /container/stop $c } do={}
    :local waited 0
    :while ([:len [/container/find where comment="MihomoProxyRoS" and stopped]] = 0 and $waited < 30) do={
        :delay 1
        :set waited ($waited + 1)
    }
    /container/remove $c
    :log warning "MihomoProxyRoS_repull: removed orphaned container entry"
}

/container/add remote-image="ghcr.io/medium1992/mihomo-proxy-ros" \
    envlists=MihomoProxyRoS mountlists=MihomoProxyRoS interface=MihomoProxyRoS \
    root-dir=$rootDir start-on-boot=yes comment="MihomoProxyRoS"

:local tries 0
:while ([:len [/container/find where comment="MihomoProxyRoS" and running]] = 0 and $tries < 60) do={
    :onerror e in={ /container/start [find where comment="MihomoProxyRoS" and stopped] } do={}
    :delay 3
    :set tries ($tries + 1)
}
:if ([:len [/container/find where comment="MihomoProxyRoS" and running]] > 0) do={
    :log warning "MihomoProxyRoS_repull: container running again"
} else={
    :log error "MihomoProxyRoS_repull: container did not start after repull"
}
