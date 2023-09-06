#!/bin/bash -e

# for all the non-essential nice to haves

apt-get update && apt-get install -y --no-install-recommends \
  irqtop \
  ripgrep \
  nfs-common

# color prompt
sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /home/comma/.bashrc
