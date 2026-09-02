# scripts-ros :: modules/16-cacert-remove.rsc
# Removes the imported Mozilla CA bundle.
#
# Only entries named cacert.pem_* are touched -- those are the ones the import
# created. Certificates the router generated itself, or that you imported by
# hand, have other names and are left alone.
#
# CloudFlare forwarders go back to verify-doh-cert=no at the same time: without
# these roots they cannot validate, and leaving verification on would silently
# turn them into forwarders that never answer.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mSkip
:global mYesNo

$mHdr "Remove root certificates"

:local ids [/certificate/find where name~"^cacert.pem" or name="CloudFlare_CA"]
:if ([:len $ids] = 0) do={
    $mOk "no imported roots present"
} else={
    :if ([$mYesNo prompt=("Remove " . [:len $ids] . " imported root certificate(s)?")] = false) do={
        $mSkip "cancelled"
    } else={
        :onerror e in={
            # Not "where verify-doh-cert=yes": RouterOS reads that property
            # back as an empty string when it is true, so such a filter matches
            # nothing and the downgrade silently never happens. Set them all.
            :local cf [/ip/dns/forwarders/find where name~"^CloudFlare"]
            :if ([:len $cf] > 0) do={
                /ip/dns/forwarders/set $cf verify-doh-cert=no
                $mOk ([:len $cf] . " CloudFlare forwarder(s) back to unverified")
            }
        } do={ $mErr "forwarder downgrade" $e }

        :onerror e in={
            /certificate/remove $ids
            $mOk ([:len $ids] . " certificate(s) removed")
        } do={ $mErr "certificates" $e }

        :onerror e in={ /file/remove [find where name="cacert.pem"] } do={}
    }
}
