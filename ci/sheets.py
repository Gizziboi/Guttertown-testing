# Contact sheets (20 screenshots a sheet, labelled with the test), every screenshot as a jpg, and a timelapse.
import sys, os, glob, shutil, subprocess
from PIL import Image, ImageDraw
out = sys.argv[1]
loop = os.path.join(out, "loop")
fr = sorted(glob.glob(os.path.join(loop, "f*.png")))
W, H = 480, 270
for k in range(0, len(fr), 20):
    sh = Image.new("RGB", (W * 5, H * 4)); d = ImageDraw.Draw(sh)
    for i, f in enumerate(fr[k:k + 20]):
        try:
            im = Image.open(f).convert("RGB").resize((W, H))
        except Exception:
            continue
        x, y = (i % 5) * W, (i // 5) * H
        sh.paste(im, (x, y))
        lab = open(f[:-4] + ".txt").read().split(" ", 1)[-1].strip() if os.path.exists(f[:-4] + ".txt") else ""
        d.text((x + 6, y + 4), "%s %s" % (os.path.basename(f)[1:6], lab), fill=(255, 255, 0))
    sh.save(os.path.join(out, "sheet_%03d.jpg" % (k // 20)), quality=80)
os.makedirs(os.path.join(out, "shots"), exist_ok=True)
for f in fr:
    try:
        Image.open(f).convert("RGB").save(os.path.join(out, "shots", os.path.basename(f)[:-4] + ".jpg"), quality=80)
    except Exception:
        pass
if fr:
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-framerate", "6", "-pattern_type", "glob", "-i", os.path.join(loop, "f*.png"),
                    "-vf", "scale=960:-2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "30", os.path.join(out, "timelapse.mp4")])
shutil.rmtree(loop, ignore_errors=True)
