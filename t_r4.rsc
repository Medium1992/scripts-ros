:global mBase "http://192.168.88.17:8000"
:local r [/tool fetch url=($mBase . "/lib.rsc") mode=http output=user as-value]
:local fn [:parse ($r->"data")]
$fn
:global mStateLoad
:global mRun
$mStateLoad
# Answer no to everything destructive, empty to every free-form question.
:global mYesNo do={ :put ("  [asked] " . $prompt . "  -> no") ; :return false }
:global mAsk do={ :return "" }
:put "######################## 30-mihomo"
$mRun "modules/30-mihomo.rsc"
:put ""
:put "######################## 50-lists"
$mRun "modules/50-lists.rsc"
