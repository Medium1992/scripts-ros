# scripts-ros :: modules/14-hardening.rsc
# Local-access hardening, lifted from the remnanode-infra bootstrap. Optional
# on a home router but free, and it closes the discovery surface that makes a
# box with a proxy container on it interesting to a neighbour.

:global mHdr
:global mOk
:global mErr
:global mYesNo

$mHdr "Hardening"

:if ([$mYesNo prompt="Disable MAC-server, neighbor discovery and legacy services?"]) do={
    :onerror e in={
        /tool/bandwidth-server/set enabled=no
        /tool/mac-server/set allowed-interface-list=none
        /tool/mac-server/mac-winbox/set allowed-interface-list=none
        /tool/mac-server/ping/set enabled=no
        /ip/neighbor/discovery-settings/set discover-interface-list=none
        $mOk "mac-server, discovery and bandwidth-server off"
    } do={ $mErr "local access" $e }

    :onerror e in={
        /ip/service/set telnet disabled=yes
        /ip/service/set ftp disabled=yes
        /ip/service/set api disabled=yes
        /ip/service/set api-ssl disabled=yes
        $mOk "telnet, ftp, api disabled"
    } do={ $mErr "services" $e }
} else={
    $mOk "skipped by operator"
}
