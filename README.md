## Building custom Ubuntu LiveUSB

TODO: fill in instructions

- `docker run --cap-add=SYS_ADMIN -v $PWD/input:/input -v $PWD/output:/output -v $PWD:/builder -w /builder -it ljfranklin/ubuntu-img-builder ./build.sh`
- `sudo dd bs=4M if=output/your-image.iso of=/dev/sda status=progress oflag=sync`
