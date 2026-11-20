# The Android screenshots on sheets (6 across): the emulator's (sheet.jpg) and the game's own (game_sheet.jpg, .061).
import sys, os, glob
from PIL import Image
out = sys.argv[1]
for sub, pat, name in [("shots", "*.png", "sheet.jpg"), ("game_shots", "*.jpg", "game_sheet.jpg")]:
    ims = []
    for f in sorted(glob.glob(os.path.join(out, sub, pat))):
        try:
            ims.append(Image.open(f).convert("RGB"))
        except Exception:
            pass
    if ims:
        w = 360
        h = int(w * ims[0].height / ims[0].width)
        sh = Image.new("RGB", (w * 6, h * ((len(ims) + 5) // 6)))
        for i, im in enumerate(ims):
            sh.paste(im.resize((w, h)), ((i % 6) * w, (i // 6) * h))
        sh.save(os.path.join(out, name), quality=80)
