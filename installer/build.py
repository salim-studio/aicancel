# Build script: icon + PyInstaller onefile exe.
# Copyright (c) 2026 salim-slimani. MIT License.
# Usage:  python installer/build.py   (run from repo root)
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "installer", "src")
DIST = os.path.join(ROOT, "dist")
WORK = os.path.join(ROOT, "build")
EXE = "aicancel-setup-1.1.0.exe"


def make_icon(path):
    from PIL import Image, ImageDraw, ImageFont
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8, 8, S - 8, S - 8], radius=52, fill=(11, 15, 25, 255),
                        outline=(34, 211, 238, 255), width=6)
    try:
        fnt = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 84)
    except Exception:
        fnt = ImageFont.load_default()
    d.text((S // 2, 118), "AI", font=fnt, fill=(241, 245, 249, 255),
           anchor="mm")
    d.line([62, 66, 194, 176], fill=(244, 63, 94, 255), width=15)
    img.save(path, sizes=[(16, 16), (32, 32), (48, 48), (64, 64),
                          (128, 128), (256, 256)])
    print("icon -> " + path)


def main():
    os.makedirs(DIST, exist_ok=True)
    ico = os.path.join(SRC, "aicancel.ico")
    make_icon(ico)

    data_files = ["aicancel.ps1", "aicancel.bat", "README.md", "LICENSE"]
    datas = []
    for name in data_files:
        src = os.path.join(ROOT, name)
        if not os.path.isfile(src):
            print("MISSING: " + src)
            return 1
        datas.append("--add-data=%s;." % src)
    datas.append("--add-data=%s;." % os.path.join(SRC, "uninstall-aicancel.ps1"))

    import PyInstaller.__main__ as pym
    args = [os.path.join(SRC, "aicancel_setup.py"),
            "--onefile", "--console",
            "--name=" + EXE.replace(".exe", ""),
            "--icon=" + ico,
            "--version-file=" + os.path.join(ROOT, "installer", "version.txt"),
            "--distpath=" + DIST,
            "--workpath=" + WORK,
            "--specpath=" + WORK,
            "--noconfirm"] + datas
    print("pyinstaller args: " + " ".join(args))
    pym.run(args)
    out = os.path.join(DIST, EXE)
    if os.path.isfile(out):
        print("BUILT %s (%d bytes)" % (out, os.path.getsize(out)))
        return 0
    print("BUILD FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
