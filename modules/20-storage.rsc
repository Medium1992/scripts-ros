# scripts-ros :: modules/20-storage.rsc
# Menu entry 2. Chooses where container root directories live and writes that
# choice into state, because every later container module needs the path and
# cannot see this module's locals across the [:parse] boundary.
#
# tmpfs is a first-class target here, not a fallback: on a router with a small
# internal flash it is often the only slot with room. The price is that a RAM
# disk is empty after a reboot, so choosing tmpfs also installs the repull
# script and its startup scheduler -- and choosing a persistent slot removes
# them again, so the two states never coexist.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mAsk
:global mYesNo
:global mFetch
:global mStateSet

$mHdr "Container storage"

# ~77 MiB, the documented floor for pulling the mihomo image.
:local minFree 80914560

:local slots [:toarray ""]
:local kinds [:toarray ""]

:if ([/system/resource/get free-hdd-space] >= $minFree) do={
    :set slots ($slots, "system")
    :set kinds ($kinds, "internal")
}
:foreach d in=[/disk/find where free>$minFree] do={
    :local fs [/disk/get $d fs]
    :if ($fs = "ext4" or $fs = "btrfs" or $fs = "tmpfs") do={
        :set slots ($slots, [/disk/get $d slot])
        :set kinds ($kinds, $fs)
    }
}

# Nothing big enough? Offer a RAM disk rather than dead-ending, since free RAM
# is usually the one resource such a router still has.
:if ([:len $slots] = 0) do={
    $mSay ("  [ !! ] no slot has " . ($minFree / 1048576) . " MiB free")
    $mSay ("         free RAM: " . ([/system/resource/get free-memory] / 1048576) . " MiB")
    :if ([$mYesNo prompt="Create a 500 MB tmpfs RAM disk now?"]) do={
        :onerror e in={
            /disk/add type=tmpfs slot=ContainerRAM tmpfs-max-size=500000000
            :delay 2
            :set slots ($slots, "ContainerRAM")
            :set kinds ($kinds, "tmpfs")
            $mOk "created tmpfs slot ContainerRAM"
        } do={ $mErr "tmpfs create" $e }
    }
}

:if ([:len $slots] = 0) do={
    $mSay "  [ !! ] no usable storage, cannot continue"
} else={

# Numbered choice: digits are the only input that is safe to type into every
# RouterOS terminal.
:local chosen ""
:local chosenKind ""
:while ([:len $chosen] = 0) do={
    $mSay ""
    $mSay "  available slots:"
    :local i 1
    :foreach s in=$slots do={
        :local free 0
        :if ($s = "system") do={
            :set free [/system/resource/get free-hdd-space]
        } else={
            :set free [/disk/get [find where slot=$s] free]
        }
        $mSay ("   " . $i . ")  " . $s . "  (" . ($kinds->($i - 1)) . ", " . ($free / 1048576) . " MiB free)")
        :set i ($i + 1)
    }
    $mSay "  select slot number:"
    :local pick [:tonum [$mAsk default=""]]
    :if ([:typeof $pick] = "num" and $pick >= 1 and $pick <= [:len $slots]) do={
        :set chosen ($slots->($pick - 1))
        :set chosenKind ($kinds->($pick - 1))
    } else={
        $mSay "  not a valid number"
    }
}

:local path ""
:if ($chosen != "system") do={ :set path ($chosen . "/") }

$mStateSet key="slot" value=$chosen
$mStateSet key="path" value=$path
$mStateSet key="fs" value=$chosenKind
$mOk ("slot " . $chosen . " (" . $chosenKind . "), container path '" . $path . "'")

# A tmpfs slot for the container temp dir is worth having regardless of where
# root-dir ends up: image extraction hammers the flash otherwise.
:if ([:len [/disk/find where fs=tmpfs and slot="ContainerTemp"]] = 0) do={
    :if ([$mYesNo prompt="Also create a separate RAM disk for container temp files?"]) do={
        :onerror e in={
            /disk/add type=tmpfs slot=ContainerTemp
            /container/config/set tmpdir=ContainerTemp/
            $mOk "tmpfs ContainerTemp, container tmpdir set"
        } do={ $mErr "ContainerTemp" $e }
    }
} else={
    $mOk "tmpfs ContainerTemp already present"
}

# --------------------------------------------------- repull, tmpfs only
:if ($chosenKind = "tmpfs") do={
    $mSay ""
    $mSay "  tmpfs is volatile: installing the startup repull job"
    :local body [$mFetch "assets/repull.rsc"]
    :if ([:len $body] = 0) do={
        $mErr "repull" "could not fetch assets/repull.rsc"
    } else={
        :onerror e in={
            :if ([:len [/system/script/find where name="MihomoProxyRoS_repull"]] = 0) do={
                /system/script/add name=MihomoProxyRoS_repull source=$body comment="sros:repull"
            } else={
                /system/script/set [find where name="MihomoProxyRoS_repull"] source=$body
            }
            $mOk "script MihomoProxyRoS_repull"
            :if ([:len [/system/scheduler/find where name="MihomoProxyRoS_repull"]] = 0) do={
                /system/scheduler/add name=MihomoProxyRoS_repull start-time=startup \
                    on-event="/system/script/run MihomoProxyRoS_repull" comment="sros:repull"
            } else={
                /system/scheduler/set [find where name="MihomoProxyRoS_repull"] \
                    start-time=startup on-event="/system/script/run MihomoProxyRoS_repull"
            }
            $mOk "scheduler MihomoProxyRoS_repull at startup"
        } do={ $mErr "repull install" $e }
    }
} else={
    :onerror e in={
        :local s [/system/script/find where name="MihomoProxyRoS_repull"]
        :local h [/system/scheduler/find where name="MihomoProxyRoS_repull"]
        :if ([:len $s] > 0 or [:len $h] > 0) do={
            /system/script/remove $s
            /system/scheduler/remove $h
            $mOk "removed repull job (storage is persistent)"
        }
    } do={ $mErr "repull cleanup" $e }
}

}
