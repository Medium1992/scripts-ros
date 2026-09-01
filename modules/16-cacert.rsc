# scripts-ros :: modules/16-cacert.rsc
# Imports the Mozilla CA bundle, so RouterOS can actually verify certificates
# that its own shipped set cannot.
#
# Why this exists: RouterOS answers "ssl: no trusted CA certificate found" for
# Cloudflare -- 1.1.1.1, one.one.one.one and cloudflare-dns.com alike -- while
# Google and Quad9 validate fine against the same store. The issuing CA is
# simply missing from the bundle RouterOS ships. Measured after importing this
# bundle, Cloudflare DoH passes with verify-doh-cert=yes three times out of
# three, and so does a verified /tool fetch.
#
# The alternative is running Cloudflare with verification off, which leaves the
# connection encrypted but unauthenticated -- and an on-path attacker is
# exactly what DoH is for, so that is not much of an alternative.
#
# Cost: about 120 entries under /certificate. That is clutter, and it is why
# this is optional rather than part of 11-dns.
#
# The import is deliberately deferred through its own [:parse]. RouterOS
# resolves file-name= when the block is parsed, not when the line runs, so an
# import written next to the download that creates the file can fail before it
# ever executes. Splitting the parse removes the question entirely.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mYesNo

$mHdr "Root certificates"

:local have [:len [/certificate/find where name~"^cacert.pem"]]
:if ($have > 0) do={
    $mOk ($have . " bundled root certificate(s) already imported")
} else={

$mSay "  RouterOS cannot verify some perfectly valid certificates, Cloudflare"
$mSay "  among them, because the issuing CA is not in the set it ships."
$mSay "  Importing the Mozilla bundle from curl.se fixes that, at the cost of"
$mSay "  around 120 entries under /certificate."
$mSay ""

:if ([$mYesNo prompt="Download and import the Mozilla CA bundle?"] = false) do={
    $mOk "skipped"
} else={

:local got false
:onerror e in={
    # This one download cannot itself be verified on a router that has no
    # usable roots yet, which is the situation being fixed. Say so plainly
    # rather than implying a guarantee that is not there.
    $mSay "  downloading https://curl.se/ca/cacert.pem (unverified, see above)"
    /tool fetch url="https://curl.se/ca/cacert.pem" mode=https check-certificate=no \
        dst-path="cacert.pem" duration=60s
    :delay 2
    :if ([:len [/file/find where name="cacert.pem"]] > 0) do={
        $mOk ("downloaded, " . [/file/get [find where name="cacert.pem"] size] . " bytes")
        :set got true
    }
} do={ $mErr "download" $e }

:if ($got) do={
    :onerror e in={
        :local imp [:parse "/certificate/import file-name=cacert.pem passphrase=\"\""]
        $imp
        :delay 2
        :local n [:len [/certificate/find where name~"^cacert.pem"]]
        $mOk ($n . " root certificate(s) imported")
        # Imported roots arrive trusted, but do not assume it.
        :local untrusted [/certificate/find where name~"^cacert.pem" and trusted=no]
        :if ([:len $untrusted] > 0) do={
            /certificate/set $untrusted trusted=yes
            $mOk ([:len $untrusted] . " marked trusted")
        }
    } do={ $mErr "import" $e }

    # The bundle is only useful once something checks against it. CloudFlare
    # was defined with verification off precisely because it could not pass;
    # now it can.
    :onerror e in={
        :local cf [/ip/dns/forwarders/find where name~"^CloudFlare" and verify-doh-cert=no]
        :if ([:len $cf] > 0) do={
            :delay 3
            /ip/dns/forwarders/set $cf verify-doh-cert=yes
            $mOk ([:len $cf] . " CloudFlare forwarder(s) now verify their certificate")
        }
    } do={ $mErr "forwarder upgrade" $e }

    :onerror e in={ /file/remove [find where name="cacert.pem"] } do={}
    $mSay ""
    $mSay "  refresh it occasionally: the bundle changes as CAs come and go."
}

}
}
