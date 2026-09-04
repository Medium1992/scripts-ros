# scripts-ros :: lists/engine.rsc
# The resource loader, installed verbatim as FWD_update, FWD_update_RU and
# IP_MihomoProxyRoS. All three do the same thing: fetch .rsc fragments and
# execute them. What differs is only WHICH fragments and where the results go,
# and that lives in a companion script named <this script>_list which the
# installer names in a one-line prefix above this body.
#
# Splitting engine from data is the whole point: the installer may replace this
# file whenever it likes, while the companion list belongs to the operator and
# is never overwritten after the first install. Editing your set of resources
# therefore never conflicts with an update.
#
# The companion list must set:
#   :global AddressList  -- firewall address-list to fill, or "" for none
#   :global ForwardTo    -- DNS forwarder for FWD entries, or "" for none
#   :global rosSets      -- array of {"base"=<url>; "items"={<name>;...}}

:global rosList
:global AddressList
:global ForwardTo
:global rosSets

:if ([:typeof $rosList] = "nothing") do={
    :log error "sros engine: rosList not set, cannot find companion list"
    :error "no companion list"
}
:if ([:len [/system/script/find where name=$rosList]] = 0) do={
    :log error ("sros engine: companion list " . $rosList . " is missing")
    :error "companion list missing"
}

:onerror e in={
    :local fn [:parse [/system/script/get [find where name=$rosList] source]]
    $fn
} do={
    :log error ("sros engine: cannot parse " . $rosList . ": " . $e)
    :error "bad companion list"
}

# One fragment. Fragments too large for a single file are published as
# <name>_part1, _part2 and so on, so every name is tried with and without the
# suffix chain until a fetch comes back empty.
:local pull do={
    :onerror e in={
        :local r [/tool fetch url=$url mode=https output=user as-value]
        :if (($r->"status") != "finished") do={ :return false }
        :local body ($r->"data")
        :if ([:len $body] = 0) do={ :return false }
        :local fn [:parse $body]
        $fn
        :log warning ($url . " loaded")
        :return true
    } do={
        :return false
    }
}

:local loaded 0
:local missing [:toarray ""]
:foreach set in=$rosSets do={
    :local base ($set->"base")
    :foreach item in=($set->"items") do={
        :if ([$pull url=($base . "/" . $item . ".rsc")]) do={
            :set loaded ($loaded + 1)
        } else={
            :set missing ($missing, $item)
        }
        :local part 1
        :local more true
        :while ($more and $part < 50) do={
            :if ([$pull url=($base . "/" . $item . "_part" . $part . ".rsc")]) do={
                :set loaded ($loaded + 1)
                :set part ($part + 1)
            } else={
                :set more false
            }
        }
    }
}

# No tagging happens here, deliberately. The upstream fragments already comment
# every entry they create with the name of the fragment -- "category-gov-ru",
# "telegram", "deepl" -- which is precisely what tells them apart from an entry
# someone added by hand, and those carry no comment at all. Stamping the
# comment-less ones would therefore claim the operator's own records, which is
# the bug this is meant to avoid: removal reads the companion list instead.

:local summary ("sros engine (" . $rosList . "): " . $loaded . " fragment(s) loaded")
:if ([:len $missing] > 0) do={
    # Naming the ones that are not there beats a bare count: a fragment can be
    # missing because it was renamed upstream, or because it never existed and
    # the companion list has a typo in it. Both are worth seeing.
    :local names ""
    :foreach m in=$missing do={
        :if ([:len $names] = 0) do={ :set names $m } else={ :set names ($names . ", " . $m) }
    }
    :set summary ($summary . "; not published upstream: " . $names)
}
:log warning $summary
:put $summary
