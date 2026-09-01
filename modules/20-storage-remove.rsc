# scripts-ros :: modules/20-storage-remove.rsc
# Forgets the storage choice and removes the RAM disks this tool created.
#
# It refuses while a container still exists, because removing the tmpfs slot a
# container lives on destroys its root-dir with no warning from RouterOS.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo
:global mStateSet

$mHdr "Remove container storage"

:local inUse [:len [/container/find]]
:if ($inUse > 0) do={
    $mSay ("  [ !! ] " . $inUse . " container(s) still exist.")
    $mSay "         Remove them first (rows 30, 40, 41), or their root-dir"
    $mSay "         disappears with the disk and RouterOS will not warn you."
} else={
    :if ([$mYesNo prompt="Remove repull job, RAM disks and the stored slot choice?"] = false) do={
        $mOk "cancelled"
    } else={
        # Any repull jobs belong to their containers and are removed with them
        # (rows 30, 40, 41). If containers are gone and jobs are left, they are
        # orphans, so sweep them.
        :onerror e in={
            :local sh [/system/scheduler/find where comment="sros:repull"]
            :local sc [/system/script/find where comment="sros:repull"]
            :if ([:len $sh] > 0 or [:len $sc] > 0) do={
                /system/scheduler/remove $sh
                /system/script/remove $sc
                $mOk "orphaned repull job(s) removed"
            }
        } do={ $mErr "repull" $e }

        :onerror e in={
            :if ([/container/config/get tmpdir] != "") do={
                /container/config/set tmpdir=""
                $mOk "container tmpdir cleared"
            }
        } do={ $mErr "tmpdir" $e }

        # Only slots this tool creates. A tmpfs the operator made themselves
        # has a different name and is left alone.
        :onerror e in={
            :foreach slot in={"ContainerTemp";"ContainerRAM"} do={
                :local d [/disk/find where slot=$slot]
                :if ([:len $d] > 0) do={
                    /disk/remove $d
                    $mOk ("RAM disk " . $slot . " removed")
                }
            }
        } do={ $mErr "ram disks" $e }

        $mStateSet key="slot" value=""
        $mStateSet key="path" value=""
        $mStateSet key="fs" value=""
        $mOk "stored slot choice cleared"
    }
}
