# Linux server on a Xiaomi Mi A1

Old Android phones actually make for pretty good mini servers. They have a battery, Wi-Fi, storage and very low idle power draw. This is how I set up my Xiaomi Mi A1 as a small headless Debian server. It ran Pi-hole, a Paper Minecraft server, Docker and LXC, all on the phone's own kernel with no VM or emulation involved.

I did this a few years ago and wrote it up later. The kernel config, the check-config outputs and the scripts in this repo are the originals. The kernel work is device-specific, but the Linux Deploy, networking, init and Docker parts should still carry over to any rooted Android phone.

Hardware and software:

- Device: Xiaomi Mi A1 (tissot), Snapdragon 625, 4 GB RAM, 64 GB storage
- ROM: LineageOS (Android 12)
- Root: KernelSU
- Kernel: Linux 4.9.337, built from ZHANtech's [Pringgodani source](https://github.com/zhantech/android_kernel_msm8953) with the config in this repo
- Distro: Debian 12 in a [Linux Deploy](https://github.com/meefik/linuxdeploy) chroot
- Docker: Termux's Android build, driven from Debian over SSH

I gave the phone a static IP in its Wi-Fi settings. Debian's SSH is on port 22 and Termux's on 8022, and they also reach each other over localhost.

## Kernel

Android kernels leave out most of what containers need: namespaces, several cgroup controllers, veth and bridge, overlayfs, seccomp filtering, so the phone needed a custom kernel.

I built on Ubuntu in WSL with [Proton Clang](https://github.com/kdrag0n/proton-clang), starting from ZHANtech's Pringgodani kernel. Proton was already unmaintained by then, but it worked fine. It took a lot of trial and error. Sometimes the kernel source was missing the driver behind an option I needed, so I'd pull the missing files from the mainline Linux tree for the same kernel version. This loop went on until the kernel actually built and check-config stopped reporting anything missing:

1. Turn options on in menuconfig, following Freddie Oliveira's [Docker on Android guide](https://gist.github.com/FreddieOliveira/efe850df7ff3951cb62d74bd770dce27).
2. Build, package with AnyKernel3, flash from TWRP.
3. Run Moby's [check-config.sh](https://github.com/moby/moby/blob/master/contrib/check-config.sh) from Termux.

The config I ended up with is [config/tissot_defconfig](config/tissot_defconfig). [config/container-support.config](config/container-support.config) is just the options I turned on, grouped by purpose, so they can be applied to a different tissot defconfig with the kernel's merge_config.sh instead of taking my whole config:

```
scripts/kconfig/merge_config.sh -m \
    arch/arm64/configs/tissot_defconfig \
    /path/to/android-linux-server/config/container-support.config
```

The final check-config runs are saved as [docs/moby-check-config.txt](docs/moby-check-config.txt) and [docs/lxc-checkconfig.txt](docs/lxc-checkconfig.txt).

[scripts/build-kernel.sh](scripts/build-kernel.sh) is what I built with. It runs the build and wraps the image in ZHANtech's [AnyKernel3 template](https://github.com/zhantech/Anykernel3-tissot) so it flashes from recovery. It runs from the kernel tree with CLANG_DIR and ANYKERNEL_DIR set. I set the kernel's local version to perf++ v1.1 so I could tell from the About screen that my build was the one running.

## Linux Deploy

Linux Deploy runs the distribution in a chroot rather than through PRoot, so Debian ran directly on the phone's kernel. I started with Ubuntu, but the app hardcodes its release list, so I was stuck on older versions unless I upgraded from inside the chroot or used one of the forks that update the list. Debian's list includes stable and oldstable, which always point at the current release, so I switched to it.

The profile settings:

- Distribution: Debian
- Architecture: arm64
- Distribution suite: stable (Debian 12 at the time)
- Installation type: Directory
- Installation path: ${ENV_DIR}/rootfs/linux
- Localization: en_US.UTF-8
- DNS: 9.9.9.9 (Quad9)
- Init: Enable, Init system sysv
  - Init level 3
  - Init user root
  - Async off
- SSH: Enable, Port 22
- Mounts, PulseAudio, GUI: off

I went with a directory install because it isn't limited to a fixed size like a disk image, and the files stay reachable from the Android side. The path is Linux Deploy's own data directory on internal storage, which is what ${ENV_DIR} expands to. SysV is there because Android holds PID 1 and systemd can't run in a chroot. The locale is set because leaving it at C had some packages complaining, and the DNS because nothing resolved until I set it.

> [!NOTE]
> Autostart is in the app's Settings screen, not in the profile. That's what starts the profile on boot.

I put services in /etc/init.d with an S link in /etc/rc3.d, and they started with the profile.

### apt and the inet group

Networking worked as root, but apt couldn't download anything. Android only lets processes in its inet group, GID 3003, use the network, and apt does its downloading as the _apt user. The fix was to put that user in the group:

```
usermod -g 3003 _apt
```

After that apt worked normally. The explanation is from [an answer on unix.stackexchange](https://unix.stackexchange.com/questions/321491/android-chroot-networking-issues).

## Docker

Docker didn't work directly inside the chroot, even with the kernel options. It expects a normal host, with cgroups mounted where Linux puts them, /var/run and a proper init system. Termux ships a [build of Docker patched for Android](https://github.com/termux/termux-root-packages/tree/master/packages/docker), with the daemon relocated under /data/docker and a wrapper that mounts the cgroup controllers itself before starting, so I ran Docker in Termux instead:

```
pkg install root-repo
pkg install docker openssh tsu
```

To bring it back after a reboot I installed [Termux:Boot](https://github.com/termux/termux-boot) and put [scripts/termux-boot.sh](scripts/termux-boot.sh) in ~/.termux/boot. The script takes a wake lock, starts dockerd with `--iptables=false` so it leaves Android's firewall rules alone, and starts sshd.

Debian doesn't have Docker installed at all. Its docker command is [scripts/docker-remote.sh](scripts/docker-remote.sh), a script that forwards whatever you type to Termux over SSH on localhost port 8022 and runs it there with sudo. I installed it as /usr/local/bin/docker and added a docker-compose link pointing at the same file, since the script runs whichever of the two it was called as:

```
sudo install scripts/docker-remote.sh /usr/local/bin/docker
sudo ln -s docker /usr/local/bin/docker-compose
```

The only other setup was putting Debian's SSH public key in Termux's authorized_keys so it doesn't ask for a password. After that, docker commands typed in Debian ran on the daemon in Termux.

## What ran on it

I installed Pi-hole barebones in Debian and pointed the router at the phone for DNS, so it served the whole network. It did its job, though the load average was high for what it was doing.

Minecraft was the real test. I ran PaperMC on Temurin JDK with Java 8 for 1.12 and Java 17 for 1.19, using a 3 GB heap and [Aikar's flags](https://docs.papermc.io/paper/aikars-flags/). A friend and I played on it. 1.12 ran fine out of the box, but 1.19 needed the world pregenerated first, since the Snapdragon 625 couldn't keep up. I did that on my PC with Chunky and copied the world over. CPU usage sat high the whole time either way.

LXC worked fine inside Debian as well.

I got Docker working but didn't use it much, since by then I had a mini PC for homelab work and moved on to that.

## Keeping it on

The phone was plugged in around the clock, so:

- I capped charging at 40% with [acc](https://github.com/VR-25/acc) and [AccA](https://github.com/MatteCarra/AccA) so the battery wouldn't be affected by sitting on the charger all the time.
- I raised zRAM from Franco Kernel Manager instead of putting a swap file on the flash.
- I used Extinguish to turn the screen off without letting the phone sleep. It needs Shizuku, which I ran as the [Sui](https://github.com/RikkaApps/Sui) module on KernelSU.

It was pretty reliable otherwise. Android would sometimes kill Linux Deploy, and turning off battery optimization for the app fixed that.

The kernel source and the AnyKernel template are ZHANtech's. The config, scripts and notes are mine.
