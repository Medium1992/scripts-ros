#!/usr/bin/env python3
"""Run commands, .rsc files, or a parse-check on the lab RouterOS box.

Credentials come from the gitignored .lab file at the repo root, never from
argv, so they stay out of shell history and out of git.

    python tools/ros.py cmd   "/system resource print"
    python tools/ros.py push  probe.rsc
    python tools/ros.py run   probe.rsc              # sftp + /import
    python tools/ros.py check lib.rsc modules/*.rsc  # parse only, no execute
"""
import sys, pathlib, paramiko

# The Windows console here is cp1251; RouterOS can echo bytes that do not map
# to it, so never let a print() kill an otherwise good run.
sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def creds():
    cfg = {}
    for line in (ROOT / ".lab").read_text().splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip()
    return cfg["HOST"], cfg["USER"], cfg["PASS"]


def connect():
    host, user, password = creds()
    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cli.connect(host, username=user, password=password, look_for_keys=False,
                allow_agent=False, timeout=15)
    return cli


def run_cmd(cli, command):
    _, out, err = cli.exec_command(command, timeout=180)
    text = out.read().decode("utf-8", "replace")
    errors = err.read().decode("utf-8", "replace")
    if text:
        print(text.rstrip())
    if errors.strip():
        print("--- stderr ---")
        print(errors.rstrip())


def push(cli, local, remote=None):
    sftp = cli.open_sftp()
    name = remote or pathlib.Path(local).name
    sftp.put(str(ROOT / local), name)
    sftp.close()
    return name


def check(cli, files):
    """Ask the router's own parser to validate each file.

    A local linter cannot know RouterOS-only rules -- empty {} is a syntax
    error, line continuations must not carry trailing spaces -- so validation
    happens on the device, parsing without executing.
    """
    lines = []
    for f in files:
        remote = "p_" + pathlib.Path(f).name
        push(cli, f, remote)
        lines.append(
            ':onerror e in={ :local fn [:parse [/file/get [find where name="%s"] contents]] ;'
            ' :put "  OK    %s" } do={ :put ("  FAIL  %s : " . $e) }' % (remote, f, f))
    run_cmd(cli, "\n".join(lines))
    run_cmd(cli, '/file/remove [find where name~"^p_"]')


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    action = sys.argv[1]
    cli = connect()
    try:
        if action == "cmd":
            run_cmd(cli, sys.argv[2])
        elif action == "push":
            print("uploaded:", push(cli, sys.argv[2]))
        elif action == "check":
            check(cli, sys.argv[2:])
        elif action == "run":
            name = push(cli, sys.argv[2])
            run_cmd(cli, "/import file-name=" + name)
        else:
            print(__doc__)
            return 1
    finally:
        cli.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
