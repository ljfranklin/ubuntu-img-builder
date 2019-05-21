FROM ubuntu:18.04

RUN \
  apt-get update && \
  apt-get install -y \
    xorriso \
    syslinux \
    squashfs-tools \
    genisoimage && \
  rm -rf /var/lib/apt/lists/*

# Define default command.
CMD ["bash"]
