# scripts-ros :: probe.rsc
# Verifies the RouterOS primitives the library is about to depend on.
# Pure ASCII, read-only except for two temp objects it removes at the end.
#
# Run:  paste into terminal, or
#   :global r [/tool fetch url=".../probe.rsc" mode=https output=user as-value]
#   :global s [:parse ($r->"data")] ; $s

:put "=== scripts-ros probe ==="
:put ("version  : " . [/system/resource/get version])
:put ("arch     : " . [/system/resource/get architecture-name])
:put ("board    : " . [/system/resource/get board-name])
:put ("free-hdd : " . [/system/resource/get free-hdd-space])
:put ("total-hdd: " . [/system/resource/get total-hdd-space])

# ---------------------------------------------------------------- 1. hashing
# md5("abc") must be 900150983cd24fb0d6963f7d28e17f72
# Three call forms, because the manual lists transform= but shows no example.
:put ""
:put "-- :convert transform=md5 (want 900150983cd24fb0d6963f7d28e17f72) --"
:local t "abc"
:onerror e in={ :put ("  form A : " . [:convert $t transform=md5 to=hex]) }        do={ :put ("  form A : FAILED " . $e) }
:onerror e in={ :put ("  form B : " . [:convert from=raw to=hex transform=md5 $t]) } do={ :put ("  form B : FAILED " . $e) }
:onerror e in={ :put ("  form C : " . [:convert $t transform=md5]) }                do={ :put ("  form C : FAILED " . $e) }
:onerror e in={ :put ("  sha512 : " . [:convert $t transform=sha512 to=hex]) }      do={ :put ("  sha512 : FAILED " . $e) }

# Hash of a realistic payload: does it survive a multi-KB string?
:local big ""
:for i from=1 to=200 do={ :set big ($big . "0123456789abcdefghij") }
:onerror e in={ :put ("  4000-char string -> " . [:convert $big transform=md5 to=hex]) } do={ :put ("  big string FAILED " . $e) }

# ------------------------------------------------------------- 2. :len bytes
# "abv" in Cyrillic, carried as base64 so this file stays ASCII.
# 3 => :len counts characters, 6 => it counts bytes (status table would break).
:put ""
:put "-- :len on multibyte --"
:put ("  ascii  'abc'      : " . [:len "abc"] . " (expect 3)")
:onerror e in={
    :local cyr [:convert "0LDQsdCy" from=base64 to=raw]
    :put ("  cyrillic 3 chars : " . [:len $cyr] . " (3=chars, 6=bytes)")
    :put ("  echoes as        : " . $cyr)
} do={ :put ("  cyrillic FAILED " . $e) }

# ------------------------------------------------------------- 3. file store
:put ""
:put "-- /file add contents= --"
:onerror e in={
    /file/add name="mpr_probe.txt" contents="hello"
    :put ("  add contents= OK, readback len=" . [:len [/file/get [find where name~"mpr_probe"] contents]])
} do={ :put ("  add contents= FAILED " . $e) }

# --------------------------------------------------------- 4. script storage
:put ""
:put "-- /system script comment + source roundtrip --"
:onerror e in={
    /system/script/add name="mpr_probe" source=":put 1" comment="mpr:probe"
    :put ("  comment property : '" . [/system/script/get [find where name="mpr_probe"] comment] . "'")
    :put ("  source readback  : '" . [/system/script/get [find where name="mpr_probe"] source] . "'")
    :put ("  find by comment  : " . [:len [/system/script/find where comment="mpr:probe"]] . " (expect 1)")
} do={ :put ("  script storage FAILED " . $e) }

# ----------------------------------------------------------------- 5. :retry
:put ""
:put "-- :retry --"
:onerror e in={ :retry command={ :put "  retry executed" } delay=1 max=2 } do={ :put ("  :retry FAILED " . $e) }

# ------------------------------------------------------- 6. fetch reachability
:put ""
:put "-- fetch + parse --"
:onerror e in={
    :local r [/tool fetch url="https://raw.githubusercontent.com/Medium1992/mihomo-proxy-ros/refs/heads/main/VERSIONS" mode=https output=user as-value]
    :put ("  github status    : " . ($r->"status") . ", bytes=" . [:len ($r->"data")])
} do={ :put ("  github FAILED " . $e) }

# ------------------------------------------------------------ 7. environment
:put ""
:put "-- container prerequisites --"
:onerror e in={ :put ("  device-mode container : " . [/system/device-mode/get container]) } do={ :put ("  device-mode FAILED " . $e) }
:put ("  container package     : " . [:len [/system/package/find where name="container" disabled=no]] . " (expect 1)")
:put ("  ext4/btrfs disks      : " . [:len [/disk/find where fs="ext4" or fs="btrfs"]])

# -------------------------------------------------------------- 8. terminal
# /terminal ask blocks when there is no tty, so it is opt-in:
#   :global mProbeAsk true   before running the probe interactively.
:global mProbeAsk
:if ([:typeof $mProbeAsk] != "nothing") do={
    :put ""
    :put "-- interactive input (type anything, then Enter) --"
    :local ans [/terminal ask]
    :put ("  got back: '" . $ans . "' len=" . [:len $ans])
}

# ------------------------------------------------------------------ cleanup
:onerror e in={ /file/remove [find where name~"mpr_probe"] } do={}
:onerror e in={ /system/script/remove [find where name="mpr_probe"] } do={}
:put ""
:put "=== probe done, temp objects removed ==="
