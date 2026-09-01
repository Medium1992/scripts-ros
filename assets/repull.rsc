# scripts-ros :: assets/repull.rsc
# Installed as <Container>_repull and run at startup, but only when the
# container lives on a tmpfs slot.
#
# A RAM disk is empty after a reboot, so the container entry survives while its
# root-dir does not. Removing the orphan and pulling again is the only way back
# to a running container.
#
# The body is shared by every container this project installs. What differs is
# a handful of globals the installing module writes as a prefix above it:
#
#   rcName        container comment, e.g. MihomoProxyRoS
#   rcImage       remote-image reference
#   rcInterface   veth to attach
#   rcEnvlists    env list name, or ""
#   rcMountlists  mount list name, or ""
#   rcCmd         container cmd, or ""
#
# The root-dir comes from sros_state rather than being baked in, so moving the
# containers to another slot needs no edit here.

:global rcName
:global rcImage
:global rcInterface
:global rcEnvlists
:global rcMountlists
:global rcCmd
:global mS

:if ([:typeof $rcName] = "nothing") do={
    :log error "sros repull: no container configured"
    :error "no container"
}

:onerror e in={
    :local fn [:parse [/system/script/get [find where name="sros_state"] source]]
    $fn
} do={
    :log error ($rcName . "_repull: cannot read sros_state, aborting")
    :error "no state"
}

:local rootDir (($mS->"path") . "Containers/" . $rcName)

:local c [/container/find where comment=$rcName]
:if ([:len $c] > 0) do={
    :onerror e in={ /container/stop $c } do={}
    :local waited 0
    :while ([:len [/container/find where comment=$rcName and stopped]] = 0 and $waited < 30) do={
        :delay 1
        :set waited ($waited + 1)
    }
    /container/remove $c
    :log warning ($rcName . "_repull: removed orphaned container entry")
}

# Three shapes cover every container here, and spelling them out beats building
# the command as a string and parsing it: a typo becomes a syntax error at
# install time instead of a container that never comes back after a reboot.
:if ([:len $rcCmd] > 0) do={
    /container/add remote-image=$rcImage interface=$rcInterface envlists=$rcEnvlists \
        cmd=$rcCmd root-dir=$rootDir start-on-boot=yes comment=$rcName
} else={
    :if ([:len $rcEnvlists] > 0 and [:len $rcMountlists] > 0) do={
        /container/add remote-image=$rcImage interface=$rcInterface envlists=$rcEnvlists \
            mountlists=$rcMountlists root-dir=$rootDir start-on-boot=yes comment=$rcName
    } else={
        :if ([:len $rcMountlists] > 0) do={
            /container/add remote-image=$rcImage interface=$rcInterface \
                mountlists=$rcMountlists root-dir=$rootDir start-on-boot=yes comment=$rcName
        } else={
            /container/add remote-image=$rcImage interface=$rcInterface \
                root-dir=$rootDir start-on-boot=yes comment=$rcName
        }
    }
}

:local tries 0
:while ([:len [/container/find where comment=$rcName and running]] = 0 and $tries < 60) do={
    :onerror e in={ /container/start [find where comment=$rcName and stopped] } do={}
    :delay 3
    :set tries ($tries + 1)
}
:if ([:len [/container/find where comment=$rcName and running]] > 0) do={
    :log warning ($rcName . "_repull: container running again")
} else={
    :log error ($rcName . "_repull: did not start after repull")
}
