# scripts-ros :: modules/17-dnstest.rsc
# Asks every DoH forwarder on this router a question and reports who answered.
#
# This exists because the answer is hardware-dependent and cannot be looked up.
# RouterOS 7.23 added HTTP/2 for DoH on ARM64 and x86/CHR only; everywhere else
# DoH still speaks HTTP/1.1, and a resolver that requires HTTP/2 simply will not
# reply there. Rather than ship a guess about which endpoints those are, this
# measures it on the device in front of you.
#
# It is also the honest way to check a forwarder before routing a domain list at
# it: a forwarder that exists is not the same as a forwarder that works.
#
# Read-only in effect but not in method -- it has to point /ip dns at each
# endpoint in turn, so it saves the resolver settings first and puts them back
# afterwards, including when a test throws.

:global mHdr
:global mOk
:global mSay
:global mErr
:global mPad

$mHdr "DNS forwarder test"

:local arch [/system/resource/get architecture-name]
$mSay ("  architecture: " . $arch)
:if ($arch = "arm64" or $arch = "x86_64") do={
    $mSay "  HTTP/2 DoH is available on this platform (7.23+)"
} else={
    $mSay "  [ !! ] HTTP/2 for DoH exists only on ARM64 and x86/CHR."
    $mSay "         Here DoH is HTTP/1.1 only, and endpoints that require"
    $mSay "         HTTP/2 will fail below. Their _udp variants still work."
}

:local sBefore [/ip/dns/get servers]
:local dBefore [/ip/dns/get use-doh-server]
:local vBefore [/ip/dns/get verify-doh-cert]

# servers= must be empty for the whole run. RouterOS silently falls back to the
# plain server list when a DoH query fails, which would turn every failure into
# a false pass.
:local tested 0
:local working 0

$mSay ""
$mSay ("  " . [$mPad "forwarder" 24] . [$mPad "result" 8] . "certificate")
:onerror outer in={
    :foreach f in=[/ip/dns/forwarders/find] do={
        :local fname [/ip/dns/forwarders/get $f name]
        :local doh [/ip/dns/forwarders/get $f doh-servers]
        :if ([:len $doh] > 0) do={
            :set tested ($tested + 1)
            :local verify true
            :if ([/ip/dns/forwarders/get $f verify-doh-cert] = false) do={ :set verify false }
            :local hits 0
            :for i from=1 to=2 do={
                :onerror e in={
                    /ip/dns/set servers="" use-doh-server=$doh verify-doh-cert=$verify
                    /ip/dns/cache/flush
                    :delay 2
                    :if ([:len [:resolve "example.com"]] > 0) do={ :set hits ($hits + 1) }
                } do={}
            }
            :local verdict "FAILS"
            :if ($hits = 2) do={
                :set verdict "ok"
                :set working ($working + 1)
            }
            :if ($hits = 1) do={ :set verdict "flaky" }
            $mSay ("  " . [$mPad $fname 24] . [$mPad $verdict 8] . "verify=" . $verify)
        }
    }
} do={ $mErr "test loop" $outer }

:onerror e in={
    /ip/dns/set servers=$sBefore use-doh-server=$dBefore verify-doh-cert=$vBefore
    /ip/dns/cache/flush
} do={ $mErr "restoring resolver settings" $e }

$mSay ""
$mOk ($working . " of " . $tested . " DoH forwarder(s) answered")
$mSay ("  resolver restored to: servers=" . [/ip/dns/get servers] . " doh=" . [/ip/dns/get use-doh-server])
:if ($working < $tested) do={
    $mSay "  the ones that failed are still fine as _udp, and a forwarder that"
    $mSay "  does not answer is not worth pointing a domain list at."
}
