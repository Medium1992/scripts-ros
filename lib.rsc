# scripts-ros :: lib.rsc
# Shared runtime for every module. Loaded first by install.rsc, always.
#
# Everything here lands in /system/script/environment as a global. Modules are
# fetched and executed through [:parse], which gives each of them its OWN scope
# -- a module cannot see the caller's :local. Globals are the only channel
# between install.rsc and the modules, hence the "m" prefix on every name and
# the single environment cleanup at the very end of install.rsc (never here,
# never in a module).
#
# Output is ASCII only. RouterOS itself does not handle multi-byte charsets in
# the console, so no localisation happens at runtime -- see docs/language.md.

# ---------------------------------------------------------------- settings
# install.rsc sets mBase before loading this file. The fallback here is only
# for loading the library on its own; it deliberately does NOT honour a
# leftover mBase, because globals persist in /system/script/environment and a
# stale one from an earlier session would quietly redirect every download.
:global mBase
:if ([:typeof $mBase] = "nothing") do={
    :global mBranch
    :if ([:typeof $mBranch] = "nothing") do={ :set mBranch "main" }
    :set mBase ("https://raw.githubusercontent.com/Medium1992/scripts-ros/refs/heads/" . $mBranch)
}

# Where the resolver goes when nothing else is answering: no container, no
# proxy, possibly no imported roots. It is chosen once (row 10) and remembered
# in state as fb_doh and fb_servers; until then these hold the default for this
# hardware.
#
# The default is architecture-dependent because DoH is. RouterOS 7.23 added
# HTTP/2 for DoH on ARM64 and x86/CHR only, so on those a DoH fallback is
# sound, and anywhere else plain DNS on 53 is the honest choice -- a fallback
# that might not speak the right protocol is not a fallback.
#
# Plain servers are kept alongside DoH deliberately: RouterOS falls back to
# them when a DoH query fails, which is exactly what you want from this entry.
#
# NSDI is never the leader. It answers SERVFAIL for every foreign name --
# github.com, ghcr.io, curl.se -- and RouterOS treats a first-server SERVFAIL
# as final rather than asking the next one, which breaks this installer, the
# image pulls and the CA download all at once.
:global mFallbackDoh ""
:global mFallbackServers "77.88.8.8,77.88.8.1"

:global mFallbackLoad do={
    :global mStateGet
    :global mFallbackDoh
    :global mFallbackServers
    :local d [$mStateGet "fb_doh"]
    :local s [$mStateGet "fb_servers"]
    :if ([:len $s] = 0) do={
        :set s "77.88.8.8,77.88.8.1"
        :local arch [/system/resource/get architecture-name]
        :if ($arch = "arm64" or $arch = "x86_64") do={
            :set d "https://common.dot.dns.yandex.net/dns-query"
        } else={
            :set d ""
        }
    }
    :set mFallbackDoh $d
    :set mFallbackServers $s
    :return true
}

# Point /ip dns at the fallback. One place, so the watchdog, the removals and
# the base module cannot drift apart on the order of the two settings -- DoH
# has to be written before servers or the resolver keeps using the old one.
:global mFallbackApply do={
    :global mFallbackDoh
    :global mFallbackServers
    :if ([:len $mFallbackDoh] > 0) do={
        /ip/dns/set use-doh-server=$mFallbackDoh verify-doh-cert=yes
    } else={
        /ip/dns/set use-doh-server="" verify-doh-cert=no
    }
    /ip/dns/set servers=$mFallbackServers
    /ip/dns/cache/flush
    :return true
}

:global mFallbackDesc do={
    :global mFallbackDoh
    :global mFallbackServers
    :if ([:len $mFallbackDoh] > 0) do={
        :return ($mFallbackDoh . " with " . $mFallbackServers . " behind it")
    }
    :return $mFallbackServers
}

# Tag written into the comment of every object we create, so uninstall and the
# status checks can find our work without a hardcoded inventory.
:global mTag "sros"

# ------------------------------------------------------------------ output
# Fixed-width markers keep the status table aligned. Do not widen them.
#   [ ok ] present and healthy     [ -- ] absent
#   [ ++ ] created just now        [ == ] already there, skipped
#   [ !! ] error                   [ upd ] update available

:global mSay do={
    :put $1
}

:global mLog do={
    :put $1
    :log warning ("sros: " . $1)
}

:global mHdr do={
    :put ""
    :put ("== " . $1)
}

# Pad $1 out to $2 columns. Never let the width go negative: [:pick] with a
# negative count does not clamp, it produces nonsense, and a name one character
# too long silently glues itself to the next column.
:global mPad do={
    :local s $1
    :local w $2
    :if ([:len $s] >= $w) do={ :return ($s . " ") }
    :return ($s . [:pick "                                        " 0 ($w - [:len $s])])
}

:global mOk   do={ :put ("  [ ++ ] " . $1) }
:global mSkip do={ :put ("  [ == ] " . $1) }
:global mMiss do={ :put ("  [ -- ] " . $1) }

:global mErr do={
    :put ("  [ !! ] " . $1 . ": " . $2)
    :log error ("sros: " . $1 . ": " . $2)
}

# ------------------------------------------------------------ idempotency
# Usage, and the reason there is no $mEnsure taking a command string: keeping
# the command as literal code means no escaping, no [:parse], and a real syntax
# error at load time instead of a runtime surprise.
#
#   :if ([$mNeed id=[/ip/dns/forwarders/find where name="Google"] name="dns:Google"]) do={
#       /ip/dns/forwarders/add name=Google doh-servers=https://8.8.8.8/dns-query
#       $mOk "dns:Google"
#   }

:global mNeed do={
    :global mSkip
    :local n 0
    :if ([:typeof $id] != "nothing") do={ :set n [:len $id] }
    :if ($n > 0) do={
        $mSkip $name
        :return false
    }
    :return true
}

# ------------------------------------------------------------------- input
# /terminal ask only works from an interactive terminal. Any module that calls
# these must declare itself interactive so the scheduler never runs it.

:global mAsk do={
    :local a [/terminal ask]
    :if ([:len $a] = 0) do={ :return $default }
    :return $a
}

:global mYesNo do={
    :while (true) do={
        :put ($prompt . " [y/n]")
        :local a [/terminal ask]
        :if ($a = "y" or $a = "yes") do={ :return true }
        :if ($a = "n" or $a = "no")  do={ :return false }
        :put "  please answer y or n"
    }
}

# ---------------------------------------------------------------- containers
# RouterOS 7.24.1 exposes no "status" property on a container: the state is
# only readable as the running / stopped flags, and "running" comes back as an
# empty string rather than false. One helper so no module has to remember that.
:global mContState do={
    :if ([:len [/container/find where comment=$1 and running]] > 0) do={ :return "running" }
    :if ([:len [/container/find where comment=$1 and stopped]] > 0) do={ :return "stopped" }
    :if ([:len [/container/find where comment=$1]] > 0) do={ :return "busy" }
    :return "absent"
}

# ------------------------------------------------------------------ hashing
# Verified on 7.24.1: [:convert <s> transform=md5 to=hex] returns the correct
# lowercase hex digest and handles multi-KB strings. Without to=hex the same
# call returns raw bytes, so the to= is not optional.
:global mHash do={
    :return [:convert $1 transform=md5 to=hex]
}

# ------------------------------------------------------- container networking
# Containers used to get a /30 each, which meant every pair of them could only
# reach each other through the router. Some of them want to be neighbours --
# something sitting next to mihomo and talking to it directly has no business
# going up to layer 3 for that -- so there is now a bridge they can share.
#
#   192.168.255.0/27   the bridge: .1 is the router, .2-.30 are containers
#   192.168.255.32+    standalone /30s, handed out in order, one per container
#
# The split at .32 is what keeps the two schemes from colliding. Addresses are
# allocated rather than hardcoded, and remembered in state, so a container keeps
# the address it was given and a second one never lands on top of it.

:global mBridgeName "ContainerBridge"
:global mBridgeCIDR "192.168.255.1/27"
:global mBridgeGW "192.168.255.1"

# The address a container ended up with. Everything that needs to point at it --
# a DNS forwarder, a route, a mangle rule -- asks here instead of assuming.
:global mNetAddr do={
    :global mStateGet
    :return [$mStateGet ("netaddr_" . $1)]
}

:global mNetEnsureBridge do={
    :global mBridgeName
    :global mBridgeCIDR
    :global mOk
    :if ([:len [/interface/bridge/find where name=$mBridgeName]] = 0) do={
        /interface/bridge/add name=$mBridgeName comment="sros:containers"
        $mOk ("bridge " . $mBridgeName . " created")
    }
    :if ([:len [/ip/address/find where address=$mBridgeCIDR]] = 0) do={
        /ip/address/add address=$mBridgeCIDR interface=$mBridgeName
        $mOk ("address " . $mBridgeCIDR . " on " . $mBridgeName)
    }
    :return true
}

# Lowest free host in .2-.30 that nothing already answers to.
:global mNetFreeOnBridge do={
    :for i from=2 to=30 do={
        :local cand ("192.168.255." . $i)
        :if ([:len [/interface/veth/find where address~("^" . $cand . "/")]] = 0) do={
            :return $cand
        }
    }
    :return ""
}

# Lowest free /30 base at or above .32, stepping by four.
:global mNetFreeP2P do={
    :local i 32
    :while ($i < 252) do={
        :local gw ("192.168.255." . ($i + 1))
        :local ct ("192.168.255." . ($i + 2))
        :if ([:len [/ip/address/find where address=($gw . "/30")]] = 0 and              [:len [/interface/veth/find where address~("^" . $ct . "/")]] = 0) do={
            :return $ct
        }
        :set i ($i + 4)
    }
    :return ""
}

# Create (or adopt) the veth for one container and put it where it belongs.
# $name is the container comment, $default is "bridge" or "standalone".
:global mNetAttach do={
    :global mOk
    :global mSay
    :global mSkip
    :global mErr
    :global mAsk
    :global mBridgeName
    :global mBridgeGW
    :global mStateSet
    :global mStateGet
    :global mNetEnsureBridge
    :global mNetFreeOnBridge
    :global mNetFreeP2P

    # Already built? Adopt whatever is really on the router rather than
    # believing state, and never renumber a container that is working.
    :local existing [/interface/veth/find where name=$cname]
    :if ([:len $existing] > 0) do={
        # Two traps in three lines. get takes an id, not the array find returns,
        # and passing the array back fails with "invalid internal item number"
        # even when it holds exactly one item. And a veth address is an array,
        # not a string, so :find on it never matches and the prefix survives --
        # which then goes into a forwarder as "192.168.253.2/30" and is
        # rejected. Force it to a string before touching it.
        :local addr [:tostr [/interface/veth/get ($existing->0) address]]
        :local ip $addr
        :local cut [:find $addr "/"]
        :if ([:typeof $cut] = "num") do={ :set ip [:pick $addr 0 $cut] }
        $mStateSet key=("netaddr_" . $cname) value=$ip
        $mSkip ("veth " . $cname . " already exists at " . $addr)
        :return $ip
    }

    :local mode $default
    $mSay ""
    $mSay ("  How should " . $cname . " be attached?")
    $mSay ("   1) bridge      share " . $mBridgeName . " with the other containers,")
    $mSay "                  so they can talk to each other directly"
    $mSay "   2) standalone  its own /30, reachable only through the router"
    $mSay ("  Enter for " . $default . ":")
    :local pick [$mAsk default=""]
    :if ($pick = "1") do={ :set mode "bridge" }
    :if ($pick = "2") do={ :set mode "standalone" }

    :local ip ""
    :local gw ""
    :if ($mode = "bridge") do={
        $mNetEnsureBridge
        :set ip [$mNetFreeOnBridge]
        :set gw $mBridgeGW
        :if ([:len $ip] = 0) do={
            $mErr $cname "no free address left on the bridge"
            :return ""
        }
        :onerror e in={
            /interface/veth/add name=$cname address=($ip . "/27") gateway=$gw
            /interface/bridge/port/add bridge=$mBridgeName interface=$cname comment="sros:containers"
            $mOk ($cname . " on " . $mBridgeName . " at " . $ip . "/27, gateway " . $gw)
        } do={
            $mErr $cname $e
            :return ""
        }
    } else={
        :set ip [$mNetFreeP2P]
        :if ([:len $ip] = 0) do={
            $mErr $cname "no free /30 left"
            :return ""
        }
        # .34 for the container means .33 for the router: the pair sits inside
        # one /30 and the router end is always one below.
        :local last [:tonum [:pick $ip ([:find $ip "255."] + 4) [:len $ip]]]
        :set gw ("192.168.255." . ($last - 1))
        :onerror e in={
            /interface/veth/add name=$cname address=($ip . "/30") gateway=$gw
            /ip/address/add address=($gw . "/30") interface=$cname
            $mOk ($cname . " standalone at " . $ip . "/30, router " . $gw)
        } do={
            $mErr $cname $e
            :return ""
        }
    }

    $mStateSet key=("netmode_" . $cname) value=$mode
    $mStateSet key=("netaddr_" . $cname) value=$ip
    $mStateSet key=("netgw_" . $cname) value=$gw
    :return $ip
}

# ------------------------------------------------------------- repull jobs
# A container on a tmpfs slot is gone after a reboot, so it needs a startup job
# that pulls it again. That job belongs to the container, not to the storage
# step -- a router with no containers should not carry one.
#
# Called with the container's own parameters; installs the job when the chosen
# slot is volatile and removes it when it is not, so the two states never
# coexist and nothing has to remember which was set up last.
:global mRepull do={
    :global mFetch
    :global mOk
    :global mErr
    :global mStateGet
    :local job ($name . "_repull")

    :if ([$mStateGet "fs"] != "tmpfs") do={
        :local sc [/system/script/find where name=$job]
        :local sh [/system/scheduler/find where name=$job]
        :if ([:len $sc] > 0 or [:len $sh] > 0) do={
            /system/scheduler/remove $sh
            /system/script/remove $sc
            $mOk ($job . " removed, storage is persistent")
        }
        :return true
    }

    :local body [$mFetch "assets/repull.rsc"]
    :if ([:len $body] = 0) do={
        $mErr $job "could not fetch assets/repull.rsc"
        :return false
    }
    :local prefix (":global rcName \"" . $name . "\"
" .         ":global rcImage \"" . $image . "\"
" .         ":global rcInterface \"" . $iface . "\"
" .         ":global rcEnvlists \"" . $envs . "\"
" .         ":global rcMountlists \"" . $mounts . "\"
" .         ":global rcCmd \"" . $cmd . "\"
")
    :onerror e in={
        :if ([:len [/system/script/find where name=$job]] = 0) do={
            /system/script/add name=$job source=($prefix . $body) comment="sros:repull"
        } else={
            /system/script/set [find where name=$job] source=($prefix . $body)
        }
        :if ([:len [/system/scheduler/find where name=$job]] = 0) do={
            /system/scheduler/add name=$job start-time=startup comment="sros:repull"                 on-event=("/system/script/run " . $job)
        }
        $mOk ($job . " installed (tmpfs is volatile)")
    } do={
        $mErr $job $e
        :return false
    }
    :return true
}

# ------------------------------------------------------------------ network
# Fetch a resource. Relative names resolve against $mBase, absolute URLs pass
# through. Returns "" on failure -- callers must check, never assume.
:global mCertWarned false
:global mFetch do={
    :global mBase
    :global mCertWarned
    :local url $1
    :if ([:pick $url 0 4] != "http") do={ :set url ($mBase . "/" . $url) }
    # mode must match the scheme: a plain-http dev server fetched with
    # mode=https fails, which is exactly how local testing gets set up.
    :local scheme "https"
    :if ([:pick $url 0 5] = "http:") do={ :set scheme "http" }

    # Everything fetched here is executed by [:parse]. That makes an
    # unverified TLS connection a code-execution channel for anyone on the
    # path, so the certificate is checked first and only dropped as a last
    # resort -- loudly, once, rather than quietly on every call.
    # Verification needs "fetch" in /certificate/settings builtin-trust-store;
    # without it RouterOS has no roots for /tool fetch at all.
    :local out ""
    :local checks {"yes";"no"}
    :if ($scheme = "http") do={ :set checks {"no"} }
    :foreach chk in=$checks do={
        :if ([:len $out] = 0) do={
            :onerror e in={
                :retry command={
                    :local r [/tool fetch url=$url mode=$scheme check-certificate=$chk output=user as-value]
                    :if (($r->"status") != "finished") do={ :error "status not finished" }
                    :set out ($r->"data")
                } delay=3 max=2
            } do={
                :if ($chk = "no") do={
                    :put ("  [ !! ] fetch " . $url . ": " . $e)
                }
            }
            :if ([:len $out] > 0 and $chk = "no" and $scheme = "https") do={
                :if ($mCertWarned = false) do={
                    :set mCertWarned true
                    :put "  [ !! ] TLS certificate could NOT be verified; continuing unverified."
                    :put "         Everything downloaded here is executed. Fix it with:"
                    :put "         /certificate/settings/set builtin-trust-store=dns,container,fetch"
                }
            }
        }
    }
    :return $out
}

# Fetch and execute a module. Returns false if anything went wrong, so the menu
# can report a failed step instead of silently continuing.
:global mRun do={
    :global mFetch
    :local body [$mFetch $1]
    :if ([:len $body] = 0) do={
        :put ("  [ !! ] module " . $1 . ": empty or unreachable")
        :return false
    }
    :local fn
    :onerror e in={ :set fn [:parse $body] } do={
        :put ("  [ !! ] module " . $1 . ": parse error: " . $e)
        :return false
    }
    :onerror e in={ $fn } do={
        :put ("  [ !! ] module " . $1 . ": runtime error: " . $e)
        :return false
    }
    :return true
}

# -------------------------------------------------------------------- state
# Installed versions and content hashes of the list scripts. Held in memory as
# the array $mS and persisted as a script named sros_state whose whole source
# is one ":global mS {...}" line -- loading it is a plain [:parse], and saving
# it is a full rewrite, which is much less code than patching one line inside
# a stored string.

:global mS
:if ([:typeof $mS] = "nothing") do={ :set mS [:toarray ""] }

:global mStateLoad do={
    :global mS
    :if ([:len [/system/script/find where name="sros_state"]] = 0) do={ :return true }
    :onerror e in={
        :local fn [:parse [/system/script/get [find where name="sros_state"] source]]
        $fn
    } do={
        :put ("  [ !! ] state load failed, starting empty: " . $e)
        :set mS [:toarray ""]
    }
    :return true
}

:global mStateSave do={
    :global mS
    :local body ":global mS {"
    :foreach k,v in=$mS do={
        :set body ($body . "\"" . $k . "\"=\"" . $v . "\";")
    }
    :set body ($body . "}")
    :if ([:len [/system/script/find where name="sros_state"]] = 0) do={
        /system/script/add name="sros_state" source=$body comment="sros:state"
    } else={
        /system/script/set [find where name="sros_state"] source=$body
    }
    :return true
}

:global mStateSet do={
    :global mS
    :global mStateSave
    :set ($mS->$key) $value
    $mStateSave
    :return true
}

:global mStateGet do={
    :global mS
    :local v ($mS->$1)
    :if ([:typeof $v] = "nothing") do={ :return "" }
    :return $v
}
