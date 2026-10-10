"""Verify image and video inputs."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--image', type=Path, required=True)
parser.add_argument('--video', type=Path, required=True)
args = parser.parse_args()
from PIL import Image
with Image.open(args.image) as image:
    image.verify()
print('Input image verified.')
subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_name,width,height', str(args.video)], check=True)
print('Input video verified.')
