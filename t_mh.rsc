:global mBase "http://192.168.88.17:8000"
:local r [/tool fetch url=($mBase . "/lib.rsc") mode=http output=user as-value]
:local fn [:parse ($r->"data")]
$fn
:global mStateLoad
:global mRun
$mStateLoad
:global mYesNo do={ :return false }
:global mAsk do={ :return "" }
:local n [:len [/container/find where comment="MihomoProxyRoS"]]
:local run [:len [/container/find where comment="MihomoProxyRoS" and running]]
:put ("mihomo before: entries=" . $n . " running=" . $run)
$mRun "modules/34-mihomo-run.rsc"
:put ""
:put ("repull jobs now: " . [:len [/system/scheduler/find where comment="sros:repull"]])
:foreach s in=[/system/scheduler/find where comment="sros:repull"] do={ :put ("  " . [/system/scheduler/get $s name]) }
