#!/usr/bin/env bash
# Monta el video de difusión: animación del logo (6 s) + recorrido de la app (24 s o 39 s),
# con un fundido de 0,4 s entre ambos. Uso: tools/video/montar_video.sh <carpeta_cuadros> <salida.mp4>
set -euo pipefail
FRAMES="${1:?carpeta de cuadros}"; OUT="${2:-docs/video/cuencauy-30s.mp4}"
INTRO="www/intro/cuencauy-intro.mp4"
ffmpeg -y -loglevel error \
  -i "$INTRO" -framerate 30 -i "$FRAMES/f%04d.jpg" \
  -filter_complex "[0:v]fps=30,scale=1920:1080:flags=lanczos,format=yuv420p,setsar=1[a];[1:v]scale=1920:1080:flags=lanczos,format=yuv420p,setsar=1[b];[a][b]xfade=transition=fade:duration=0.4:offset=5.6[v]" \
  -map "[v]" -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "Video: $OUT"
