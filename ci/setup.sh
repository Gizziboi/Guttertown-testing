#!/usr/bin/env bash
# Runner packages (quiet: nothing about the build goes to the public log).
TAG=$1
if [ "$TAG" = "linux" ] || [ "$TAG" = "android" ]; then
  sudo apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq xvfb imagemagick ffmpeg mesa-vulkan-drivers libgl1-mesa-dri libxcursor1 libxinerama1 libxrandr2 libxi6 python3-pil >/dev/null 2>&1
else
  brew install ffmpeg coreutils >/dev/null 2>&1 || true
  python3 -m pip install --break-system-packages -q pillow >/dev/null 2>&1 || python3 -m pip install -q pillow >/dev/null 2>&1 || true
fi
echo "setup done"
