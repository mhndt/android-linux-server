#!/data/data/com.termux/files/usr/bin/sh

termux-wake-lock
sudo dockerd --iptables=false >>"$HOME/.termux/dockerd.log" 2>&1 &
sshd
