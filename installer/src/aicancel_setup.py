# aicancel setup — installer entry point.
# Copyright (c) 2026 salim-slimani. Licensed under the MIT License.
# https://github.com/salim-studio/aicancel
"""Installs aicancel (ps1 + launcher + docs) to Program Files,
creates Start Menu / Desktop shortcuts, registers Add/Remove Programs,
and optionally runs the tool (full removal or scan-only preview)."""

import argparse
import ctypes
import os
import shutil
import subprocess
import sys

APP = "aicancel"
VER = "1.1.0"
PUBLISHER = "salim-slimani"
URL = "https://github.com/salim-studio/aicancel"
BUNDLED = ["aicancel.ps1", "aicancel.bat", "README.md", "LICENSE",
           "uninstall-aicancel.ps1"]

BANNER = r"""
   ============================================
    a i c a n c e l   setup  v%s
    Cancel Windows AI - clean. private. yours.
    (c) 2026 salim-slimani - MIT
   ============================================
""" % VER


def bundled_path(name):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    p = os.path.join(base, name)
    if not os.path.isfile(p):  # dev layout: installer/src/../../<file>
        alt = os.path.normpath(os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "..", name))
        if os.path.isfile(alt):
            return alt
    return p


def is_admin():
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def relaunch_as_admin():
    params = " ".join('"%s"' % a for a in sys.argv[1:])
    exe = sys.executable if getattr(sys, "frozen", False) else sys.executable
    script = "" if getattr(sys, "frozen", False) else '"%s" ' % os.path.abspath(sys.argv[0])
    ctypes.windll.shell32.ShellExecuteW(None, "runas", exe,
                                        "%s%s" % (script, params), None, 1)
    sys.exit(0)


def default_dest():
    pf = os.environ.get("ProgramFiles", r"C:\Program Files")
    return os.path.join(pf, "aicancel")


def ps_run(cmd):
    return subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy",
                           "Bypass", "-Command", cmd],
                          capture_output=True, text=True)


def make_shortcut(lnk, target, args, workdir, icon):
    cmd = (
        "$w = New-Object -ComObject WScript.Shell; "
        "$s = $w.CreateShortcut('%s'); "
        "$s.TargetPath = '%s'; $s.Arguments = '%s'; "
        "$s.WorkingDirectory = '%s'; $s.IconLocation = '%s'; "
        "$s.Description = 'aicancel - Cancel Windows AI'; $s.Save()" %
        (lnk.replace("'", "''"), target, args.replace("'", "''"),
         workdir.replace("'", "''"), icon))
    r = ps_run(cmd)
    return r.returncode == 0 and os.path.isfile(lnk)


def install(dest, desktop=True, startmenu=True):
    os.makedirs(dest, exist_ok=True)
    for name in BUNDLED:
        src = bundled_path(name)
        if not os.path.isfile(src):
            print("  [x] missing bundled file: %s" % name)
            return False
        shutil.copy2(src, os.path.join(dest, name))
    print("  [+] files installed to %s" % dest)

    ps1 = os.path.join(dest, "aicancel.ps1")
    ps_exe = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                          "System32", "WindowsPowerShell", "v1.0",
                          "powershell.exe")
    args = '-NoProfile -ExecutionPolicy Bypass -File "%s" -Backup -EnableLog' % ps1
    if startmenu:
        sm = os.path.join(os.environ.get("ProgramData", r"C:\ProgramData"),
                          r"Microsoft\Windows\Start Menu\Programs",
                          "aicancel.lnk")
        print("  [+]" if make_shortcut(sm, ps_exe, args, dest, ps_exe)
              else "  [!]", "Start Menu shortcut")
    if desktop:
        dt = os.path.join(os.environ.get("PUBLIC", r"C:\Users\Public"),
                          "Desktop", "aicancel.lnk")
        print("  [+]" if make_shortcut(dt, ps_exe, args, dest, ps_exe)
              else "  [!]", "Desktop shortcut")

    arp = r"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\aicancel"
    uninst = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
              '"%s"' % os.path.join(dest, "uninstall-aicancel.ps1"))
    kv = [("DisplayName", "REG_SZ", "aicancel %s" % VER),
          ("DisplayVersion", "REG_SZ", VER),
          ("Publisher", "REG_SZ", PUBLISHER),
          ("URLInfoAbout", "REG_SZ", URL),
          ("InstallLocation", "REG_SZ", dest),
          ("UninstallString", "REG_SZ", uninst),
          ("NoModify", "REG_DWORD", "1"),
          ("NoRepair", "REG_DWORD", "1")]
    for n, t, d in kv:
        subprocess.run(["reg.exe", "add", arp, "/v", n, "/t", t, "/d", d,
                        "/f"], capture_output=True)
    print("  [+] registered in Add/Remove Programs")
    return True


def run_tool(dest, mode):
    ps1 = os.path.join(dest, "aicancel.ps1")
    if mode == "full":
        args = [ps1, "-NonInteractive", "-All", "-Backup", "-EnableLog"]
    elif mode == "scan":
        args = [ps1, "-ScanOnly", "-NonInteractive", "-All"]
    else:
        return 0
    print("  [*] launching aicancel (%s)..." % mode)
    return subprocess.run(["powershell.exe", "-NoProfile",
                           "-ExecutionPolicy", "Bypass",
                           "-File"] + args).returncode


def do_uninstall(dest):
    ps1 = os.path.join(dest, "uninstall-aicancel.ps1")
    if os.path.isfile(ps1):
        return subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", ps1]).returncode
    return 1


def menu():
    print("  1) Install only")
    print("  2) Install + full removal (recommended)")
    print("  3) Install + scan-only preview")
    print("  4) Uninstall aicancel")
    print("  0) Exit")
    return input("  Pick a number: ").strip()


def main():
    ap = argparse.ArgumentParser(prog="aicancel-setup",
                                 description="aicancel %s installer" % VER)
    ap.add_argument("--silent", action="store_true",
                    help="install without running the tool")
    ap.add_argument("--run-full", action="store_true",
                    help="install then run full removal")
    ap.add_argument("--run-scan", action="store_true",
                    help="install then run scan-only preview")
    ap.add_argument("--uninstall", action="store_true", help="uninstall")
    ap.add_argument("--dest", default=None, help="install directory")
    ap.add_argument("--no-desktop", action="store_true")
    ap.add_argument("--no-startmenu", action="store_true")
    a = ap.parse_args()

    dest = a.dest or default_dest()
    if not is_admin():
        print(BANNER)
        print("  Administrator rights required - relaunching as admin...")
        relaunch_as_admin()

    if a.uninstall:
        print(BANNER)
        sys.exit(do_uninstall(dest))

    mode = None
    if a.run_full:
        mode = "full"
    elif a.run_scan:
        mode = "scan"
    elif not a.silent:
        print(BANNER)
        c = menu()
        if c == "1":
            mode = None
        elif c == "2":
            mode = "full"
        elif c == "3":
            mode = "scan"
        elif c == "4":
            sys.exit(do_uninstall(dest))
        else:
            print("  Cancelled.")
            return 0
    else:
        print(BANNER)

    print("  [*] installing aicancel %s to %s ..." % (VER, dest))
    if not install(dest, desktop=not a.no_desktop,
                   startmenu=not a.no_startmenu):
        print("  [x] install failed.")
        return 1
    print("  [+] installed.")
    if mode:
        return run_tool(dest, mode)
    print("  Tip: run 'aicancel' from the Start Menu, or re-run this")
    print("  setup and pick option 2/3.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
