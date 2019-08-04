#!/bin/bash
#
# This script just outputs the ldd results when it is ran on the email
# binary. It's a minimal one that only needs openssl.

cat << EOF
        linux-vdso.so.1 (0x00007ffc57ff9000)
        libcrypto.so.1 => /lib64/libcrypto.so.1 (0x00007fb25aeb9000)
        libssl.so.1 => /lib64/libssl.so.1 (0x00007fb25ac46000)
        libm.so.6 => /lib64/libm.so.6 (0x00007fb25a93d000)
        libc.so.6 => /lib64/libc.so.6 (0x00007fb25a574000)
        libdl.so.2 => /lib64/libdl.so.2 (0x00007fb25a370000)
        /lib64/ld-linux-x86-64.so.2 (0x00007fb25b312000)
EOF

