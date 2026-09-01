# scripts-ros :: modules/20-storage.rsc
# Chooses where container root directories live, and whether image unpacking
# uses a RAM disk.
#
# Two decisions, asked in that order and announced up front, because they are
# easy to confuse: both can involve a RAM disk, and an earlier version offered
# to create one twice at two unrelated moments.
#
# The choice goes into state because every container module needs the path and
# cannot see this module's locals across the [:parse] boundary.
#
# Nothing about any particular container belongs here. A tmpfs slot means the
# containers on it need a startup job to survive a reboot, but that job is the
# container's own business -- rows 30, 40 and 41 install it for themselves.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mAsk
:global mYesNo
:global mPad
:global mStateSet
:global mStateGet

$mHdr "Container storage"

# ~77 MiB, the documented floor for pulling the mihomo image.
:local minFree 80914560

# ------------------------------------------------------- what is here now
:local tmpdir [/container/config/get tmpdir]
$mSay ""
$mSay "  storage on this router:"
$mSay ("    " . [$mPad "internal flash" 16] . ([/system/resource/get free-hdd-space] / 1048576) . " MiB free")
:foreach d in=[/disk/find] do={
    :local note ([/disk/get $d fs] . ", " . ([/disk/get $d free] / 1048576) . " MiB free")
    :if ([/disk/get $d fs] = "tmpfs") do={ :set note ($note . ", volatile") }
    $mSay ("    " . [$mPad [/disk/get $d slot] 16] . $note)
}
:if ([:len $tmpdir] > 0) do={
    $mSay ("    container temp files currently go to " . $tmpdir)
}
$mSay ""
$mSay "  two things are decided here:"
$mSay "    1. where container root directories live"
$mSay "    2. whether image unpacking uses a RAM disk instead of flash"

# ------------------------------------------------ 1. the root directory
$mSay ""
$mSay "  --- 1. root directory ---"

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

:local chosen ""
:local chosenKind ""
:local current [$mStateGet "slot"]

:while ([:len $chosen] = 0) do={
    $mSay ""
    :if ([:len $slots] = 0) do={
        $mSay ("  nothing has the " . ($minFree / 1048576) . " MiB a container image needs.")
    } else={
        $mSay ("  slots with at least " . ($minFree / 1048576) . " MiB free:")
    }
    :local i 1
    :foreach sName in=$slots do={
        :local free 0
        :if ($sName = "system") do={
            :set free [/system/resource/get free-hdd-space]
        } else={
            :set free [/disk/get [find where slot=$sName] free]
        }
        :local note (($kinds->($i - 1)) . ", " . ($free / 1048576) . " MiB free")
        :if (($kinds->($i - 1)) = "tmpfs") do={ :set note ($note . ", volatile") }
        :if ($sName = $current) do={ :set note ($note . "   <- currently used") }
        $mSay ("   " . [$mPad ($i . ")") 5] . [$mPad $sName 14] . $note)
        :set i ($i + 1)
    }
    # Creating a RAM disk is one of the options, not a separate question asked
    # somewhere else. Free RAM is usually what a small router still has.
    $mSay ("   " . [$mPad ($i . ")") 5] . [$mPad "new RAM disk" 14] . "create a 500 MB tmpfs, volatile, " . ([/system/resource/get free-memory] / 1048576) . " MiB RAM free")
    $mSay "  choose a number:"

    :local pick [:tonum [$mAsk default=""]]
    :if ([:typeof $pick] != "num") do={
        $mSay "  that is not a number"
    } else={
        :if ($pick = $i) do={
            :onerror e in={
                /disk/add type=tmpfs slot=ContainerRAM tmpfs-max-size=500000000
                :delay 2
                :set chosen "ContainerRAM"
                :set chosenKind "tmpfs"
                $mOk "created RAM disk ContainerRAM"
            } do={ $mErr "tmpfs create" $e }
        } else={
            :if ($pick >= 1 and $pick < $i) do={
                :set chosen ($slots->($pick - 1))
                :set chosenKind ($kinds->($pick - 1))
            } else={
                $mSay "  no such number in the list"
            }
        }
    }
}

:local path ""
:if ($chosen != "system") do={ :set path ($chosen . "/") }
$mStateSet key="slot" value=$chosen
$mStateSet key="path" value=$path
$mStateSet key="fs" value=$chosenKind
$mOk ("root directories go to slot " . $chosen . " (" . $chosenKind . "), path '" . $path . "'")
:if ($chosenKind = "tmpfs") do={
    $mSay "         it is volatile: each container installed on it will get a"
    $mSay "         startup job that pulls it again after a reboot."
}

# --------------------------------------------------- 2. temporary files
$mSay ""
$mSay "  --- 2. temporary files ---"

# Already pointed at a RAM disk? Then there is nothing to ask. Checking the
# setting rather than one hardcoded slot name matters: a router set up by hand,
# or by the older script, may already use a differently named tmpfs.
:local tmpOk false
:if ([:len $tmpdir] > 0) do={
    :foreach d in=[/disk/find where fs=tmpfs] do={
        :local slotName [/disk/get $d slot]
        :if ($tmpdir = ($slotName . "/") or $tmpdir = ("/" . $slotName) or $tmpdir = $slotName) do={
            :set tmpOk true
        }
    }
}

:if ($tmpOk) do={
    $mOk ("already unpacking images in RAM, at " . $tmpdir)
} else={
    $mSay "  unpacking images in RAM spares the flash and is faster."
    :if ([$mYesNo prompt="Create a RAM disk for container temp files?"]) do={
        :onerror e in={
            :if ([:len [/disk/find where slot="ContainerTemp"]] = 0) do={
                /disk/add type=tmpfs slot=ContainerTemp
                :delay 2
            }
            /container/config/set tmpdir=ContainerTemp/
            $mOk "temp files go to the RAM disk ContainerTemp"
        } do={ $mErr "ContainerTemp" $e }
    } else={
        $mOk "temp files stay on flash"
    }
}

$mSay ""
$mOk ("storage settled: root " . $chosen . ", temp " . [/container/config/get tmpdir])
