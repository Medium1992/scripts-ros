# scripts-ros :: modules/16-cacert.rsc
# Adds the root certificates RouterOS is missing, so verification can actually
# succeed instead of being switched off.
#
# The concrete problem, measured rather than assumed: the Cloudflare DNS
# certificate chains to "SSL.com Root Certification Authority ECC", and that
# root is not in the set RouterOS ships. So https://1.1.1.1/dns-query fails
# with "ssl: no trusted CA certificate found" while Google (GTS Root R4 ->
# GlobalSign Root CA) and Yandex (GlobalSign Root CA - R3) validate fine
# against the very same store.
#
# Two ways to fix it:
#
#   targeted  import only the roots this project actually needs. They are
#             committed to the repository with their sha256 in the header, so
#             what gets installed is reviewable and does not change under you.
#             One certificate, and Cloudflare then passes 3/3 with
#             verify-doh-cert=yes.
#   bundle    import the whole Mozilla set from curl.se. Fixes anything, costs
#             about 120 entries under /certificate, and the download itself
#             cannot be verified on a router that has no usable roots yet.
#
# CRL is deliberately left alone. /certificate settings ships with
# crl-download=no and crl-use=no, verification works without it, and turning it
# on means every check depends on reaching a CRL distribution point -- a new
# way for DNS to break, on a router whose DNS you are in the middle of fixing.
#
# The import is deferred through its own [:parse]: file-name= is resolved when
# the block is parsed, not when the line runs, so an import written next to the
# download that creates the file can fail before it ever executes.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mAsk
:global mFetch
:global mSkip

$mHdr "Root certificates"

# name in the repository | name to give it on the router | what it unblocks
:local targeted {
    {"file"="sslcom-ecc-root"; "as"="CloudFlare_CA"; "why"="Cloudflare DoH"}
}

:local haveBundle [:len [/certificate/find where name~"^cacert.pem"]]
:local haveTargeted 0
:foreach t in=$targeted do={
    :set haveTargeted ($haveTargeted + [:len [/certificate/find where name=($t->"as")]])
}

# Nothing to ask when there is nothing missing. An installer that offers a
# choice and then answers "already present" to every option is just noise.
:local pick "3"
:if ($haveTargeted > 0 or $haveBundle > 0) do={
    :if ($haveBundle > 0) do={
        $mSkip ($haveBundle . " root(s) from the Mozilla bundle already imported")
    } else={
        $mSkip ($haveTargeted . " targeted root(s) already imported, nothing missing")
    }
} else={
    $mSay ""
    $mSay "  RouterOS cannot verify some perfectly valid certificates -- the"
    $mSay "  Cloudflare chain among them -- because the issuing CA is not in"
    $mSay "  the set it ships. Two ways to fix that:"
    $mSay ""
    $mSay "   1) targeted  just the roots this project needs, pinned in the repo"
    $mSay "   2) bundle    the whole Mozilla set from curl.se, about 120 entries"
    $mSay "   3) skip      leave Cloudflare failing its certificate check"
    $mSay "  choose, or Enter for 1:"
    :set pick [$mAsk default="1"]
    :if ([:len $pick] = 0) do={ :set pick "1" }
    :if ($pick != "1" and $pick != "2" and $pick != "3") do={
        $mSay ("  '" . $pick . "' is not one of the three, taking 1")
        :set pick "1"
    }
    $mSay ("  -> " . $pick)
}

# Import a PEM that is already on the router, then give it a name worth reading
# in /certificate print.
:global mImportPem do={
    :global mOk
    :global mErr
    :onerror e in={
        :local imp [:parse ("/certificate/import file-name=" . $file . " passphrase=\"\"")]
        $imp
        :delay 2
        :local fresh [/certificate/find where name~("^" . $file)]
        :if ([:len $fresh] = 0) do={
            $mErr $as "import produced no certificate"
            :return false
        }
        :foreach c in=$fresh do={
            /certificate/set $c name=$as trusted=yes
        }
        $mOk ($as . " imported and trusted")
        :return true
    } do={
        $mErr $as $e
        :return false
    }
}
:global mImportPem

:if ($pick = "1") do={
    :foreach t in=$targeted do={
        :if ([:len [/certificate/find where name=($t->"as")]] > 0) do={
            $mOk (($t->"as") . " already present")
        } else={
            :local body [$mFetch ("assets/ca/" . ($t->"file") . ".pem")]
            :if ([:len $body] = 0) do={
                $mErr ($t->"as") "could not fetch the certificate from the repository"
            } else={
                :local fname (($t->"file") . ".pem")
                :onerror e in={
                    /file/remove [find where name=$fname]
                } do={}
                :onerror e in={
                    /file/add name=$fname contents=$body
                    :delay 2
                    $mImportPem file=$fname as=($t->"as")
                    /file/remove [find where name=$fname]
                    $mSay ("    unblocks: " . ($t->"why"))
                } do={ $mErr ($t->"as") $e }
            }
        }
    }
} else={
:if ($pick = "2") do={
    :if ($haveBundle > 0) do={
        $mOk "bundle already imported"
    } else={
        :local got false
        :onerror e in={
            $mSay "  downloading https://curl.se/ca/cacert.pem"
            $mSay "  (this one download cannot be verified -- a router without"
            $mSay "   usable roots is exactly the situation being repaired)"
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
                $mOk ([:len [/certificate/find where name~"^cacert.pem"]] . " root certificate(s) imported")
                :local untrusted [/certificate/find where name~"^cacert.pem" and trusted=no]
                :if ([:len $untrusted] > 0) do={
                    /certificate/set $untrusted trusted=yes
                    $mOk ([:len $untrusted] . " marked trusted")
                }
            } do={ $mErr "import" $e }
            :onerror e in={ /file/remove [find where name="cacert.pem"] } do={}
            $mSay "  refresh it occasionally: the bundle changes as CAs come and go."
        }
    }
} else={
    $mOk "skipped, Cloudflare will keep failing its certificate check"
}
}

# Verification is only worth anything once something checks against it. With
# the roots present, the verifying CloudFlare forwarders can finally answer.
:if ($pick = "1" or $pick = "2") do={
    :delay 3
    :onerror e in={
        :local n 0
        :foreach f in=[/ip/dns/forwarders/find where name~"^CloudFlare"] do={
            :if ([/ip/dns/forwarders/get $f verify-doh-cert] = false) do={
                :if ([:typeof [:find [/ip/dns/forwarders/get $f name] "_noverify"]] != "num") do={
                    /ip/dns/forwarders/set $f verify-doh-cert=yes
                    :set n ($n + 1)
                }
            }
        }
        :if ($n > 0) do={ $mOk ($n . " CloudFlare forwarder(s) now verify their certificate") }
    } do={ $mErr "forwarder upgrade" $e }
}
