:global mBase "http://192.168.88.17:8000"
:local r [/tool fetch url=($mBase . "/lib.rsc") mode=http output=user as-value]
:local fn [:parse ($r->"data")]
$fn
:global mStateLoad
:global mStateSet
:global mRun
$mStateLoad
$mStateSet key="slot" value="tmp1"
$mStateSet key="path" value="tmp1/"
$mStateSet key="fs" value="tmpfs"
# Decline the resolver takeover: this router's DNS is not mine to repoint.
:global mYesNo do={ :put ("  [answered no] " . $prompt) ; :return false }
:global mAsk do={ :return "" }
:put ("free RAM before: " . ([/system/resource/get free-memory] / 1048576) . " MiB, tmp1 free: " . ([/disk/get [find where slot="tmp1"] free] / 1048576) . " MiB")
$mRun "modules/41-adguard.rsc"
:put ""
:put ("free RAM after : " . ([/system/resource/get free-memory] / 1048576) . " MiB, tmp1 free: " . ([/disk/get [find where slot="tmp1"] free] / 1048576) . " MiB")
:put ("repull jobs: " . [:len [/system/scheduler/find where comment="sros:repull"]])
:foreach s in=[/system/scheduler/find where comment="sros:repull"] do={ :put ("  " . [/system/scheduler/get $s name]) }
