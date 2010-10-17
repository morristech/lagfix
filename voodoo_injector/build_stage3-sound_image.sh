#!/bin/sh

cd output/target

find \
        usr/lib/libasound* \
        usr/share/alsa/alsa.conf \
        usr/bin/aplay \
        usr/bin/madplay \
        usr/lib/libmad* \
        usr/lib/libid3* \
        usr/lib/libz* \
        | cpio -v -H newc -o | lzma -9  > stage3-sound.cpio.lzma

