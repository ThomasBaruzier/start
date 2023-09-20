#!/bin/bash

diskSel() {

  while true; do

    echo -e '\nDisks available for installation:\n'
    diskList=$(fdisk -l)
    readarray -t disks <<< $(grep -E -o '^Disk /dev/[^,]+' <<< "$diskList" | grep -v '^Disk /dev/loop')
    for ((i=0; i < "${#disks[@]}"; i++)); do
      choiceList[i]=$(echo "[$i] - $(grep -b1 "${disks[i]}" <<< "$diskList" | tail -n 1 | grep -Po '(?<=: ).+' | sed 's: *$::g') - ${disks[i]:6}")
    done
    printf '%s\n' "${choiceList[@]}"
    echo
    read -p 'Option (m for more info) (default=0): ' x
    echo
    if [ "$x" = m ]; then
     clear && fdisk -l
     continue
    elif [ "$x" = '' ]; then
      x=0
    fi
    disk="${disks[x]:6}"
    if [[ -n "$disk" && "$x" =~ [0-9]+ ]]; then
      disk="/$(grep -E -o '^[^: ]+' <<< "$disk")"
      echo -e "> \e[32mSelected ${choiceList[x]:6}\e[0m\n"
      break
    else
      echo -e "> \e[31mERROR: Invalid selection\e[0m"
    fi

  done

  efi=$(fdisk -l "$disk" | tail -n 3 | grep 'EFI System' | awk '{print $1}')
  filesystem=$(fdisk -l "$disk" | tail -n 3 | grep 'Linux filesystem' | awk '{print $1}')
  umount -l -q "$efi" "$filesystem" >> log 2>&1

}

if whoami | grep -q 'u0_'; then # Termux

  # init
  clear
  echo -en '\e[33mWARNING: This script was made for fresh TERMUX installs. Otherwise, expect your system to break.\e[0m\n\nContinue? (default=n): '
  read x; [ "$x" != y ] && echo && exit
  [ ! -d ~/storage ] && termux-setup-storage
  touch ~/.hushlogin

  # edit sources
  echo -en '\nAdd apt sources? (default=y): '; read x; [ "$x" != n ] && \
    echo -e 'deb https://packages-cf.termux.dev/apt/termux-main/ stable main\ndeb https://packages.termux.dev/apt/termux-main/ stable main\ndeb https://cdn.lumito.net/termux/termux-main stable main' > ~/../usr/etc/apt/sources.list

  # update
  echo -en '\nUpdate? (default=y): '; read x; [ "$x" != n ] && echo && \
    apt update -o DPkg::Options::="--force-confnew" -y && \
    apt upgrade -o DPkg::Options::="--force-confnew" -y && \
    pkg update -o DPkg::Options::="--force-confnew" -y && \
    pkg upgrade -o DPkg::Options::="--force-confnew" -y
  mkdir -p ~/.temp ~/.temp/trash
  rm ~/storage/ -rf

  # packages
  echo -en "\nInstall packages? (default=y): "
  read x; [ "$x" != n ] && \
  apt install wget nano python3 p7zip zip unzip nmap \
      proot-distro git wget man htop tree mediainfo \
      nodejs ffmpeg file lynx jq bc whois openssh android-tools \
      -o DPkg::Options::="--force-confnew" -y && \
      npm install -g npm@latest peerflix

  # backup
  echo -en "\nExtract backup? (default=n): "
  read x; echo "$x" | grep -E -q '.{8,}' && \
    curl -#L '1o2.ir/bkp-prv' --http1.1 > backup.7z && \
    apt install -y p7zip && \
    7z x backup.7z -o"$HOME" -p"$x" -y && \
    rm -rf ~/backup.7z
  [ "$x" = y ] && \
    curl -#L '1o2.ir/bkp-pub' --http1.1 > backup.7z && \
    apt install -y p7zip && \
    7z x backup.7z -o"$HOME" -y && \
    rm -rf ~/backup.7z

  # java
  echo -en "\nInstall java? (default=n): "
  read x; [ "$x" = y ] && \
  curl -s 'https://raw.githubusercontent.com/MasterDevX/java/master/installjava' -o javainstall && \
  bash javainstall && \
  rm -rf javainstall ~/.profile

  # pip
  echo -en "\nInstall pip and its packages? (default=n): "
  read x; [ "$x" = y ] && \
  pip install --upgrade pip && \
  pip install -U --force spotdl==4.0.0rc3

  # vm
  echo -en "\nInstall ubuntu vm? (default=n): "
  read x; [ "$x" = y ] && \
  apt install proot-distro && \
  proot-distro install ubuntu

  # end
  wait; pkill -4 bash

elif [[ $(arch-chroot 2>&1) == '==> ERROR: No chroot directory specified' ]]; then # arch iso

  # init
  clear
  read -p $'\e[33mWARNING: This script was made for ARCH ISOs. Otherwise, expect your system to break.\nAlso, there is a high chance of breaking your system by skipping steps or setting up multiple users.\e[0m\nContinue? (default=n): ' x

  if [ "$x" != chroot ]; then

    [ "$x" != y ] && echo -e '\nExiting...\n' && exit

    # internet check
    echo
    if ping google.com -c1 >> log 2>&1; then
      echo '> Connected to the internet'
    else
      echo -e '> \e[31mERROR: Not connected to the internet. Please verify your connection and try again\e[0m\n'
      exit
    fi

    # sync date
    timedatectl set-ntp true
    while timedatectl status | grep -q 'System clock synchronized: no'; do
      [ "$tries" = 20 ] && echo 'Time clock failed to synchronize... && exit'
      ((tries++))
      sleep 0.5
    done
    echo -e '> Time clock successfully synchronized'

    # disk selection
    diskSel

    # partitionning
    read -p $'Format ALL disk and setup partitions?\n\e[31m(WARNING: THERE IS NO COMMING BACK)\e[0m (default=n): ' x
    [ "$x" != y ] && echo -e '\nExiting...\n' && exit
    echo

    while true; do
      read -p $'\e[35mEFI SYSTEM\e[0m partition size (default:512M): ' efiSize
      [ "$efiSize" = e ] && echo -e '\nExiting...' && exit
      if [[ -z "$efiSize" ]]; then
        efiSize='+512M'
        break
      elif [[ "${efiSize:u}" =~ ^[0-9]+[K|M|G|T|P]$ ]]; then
        efiSize="+${efiSize:u}"
        break
      else
        echo -e '\n> \e[31mERROR: Invalid input\e[0m\n'
      fi
    done

    while true; do
      read -p $'\e[35mSWAP\e[0m partition size (default:2G) (s to skip): ' swapSize
      [ "$swapSize" = e ] && echo -e '\nExiting...' && exit
      if [[ -z "$swapSize" ]]; then
        swapSize='+2G'
        break
      elif [[ "${swapSize:u}" =~ ^[0-9]+[K|M|G|T|P]$ ]]; then
        swapSize="+${swapSize:u}"
        break
      elif [ "$swapSize" = s ]; then
        echo -e '\e[33mWARNING: Skipping the swap partition\e[0m'
	      swapLess=true
        break
      else
        echo -e '\n> \e[31mERROR: Invalid input\e[0m\n'
      fi
    done

    while true; do
      read -p $'\e[35mROOT\e[0m partition size (default:remaining disk space): ' rootSize
      [ "$rootSize" = e ] && echo -e '\nExiting...' && exit
      if [[ -z "$rootSize" ]]; then
        unset rootSize
        break
      elif [[ "${rootSize:u}" =~ ^[0-9]+[K|M|G|T|P]$ ]]; then
        rootSize="+${rootSize:u}"
        break
      else
        echo -e '\n> \e[31mERROR: Invalid input\e[0m\n'
      fi
    done

    swapoff -a
    dd if=/dev/zero of="$disk" bs=512 count=1 conv=notrunc >> log 2>&1
    if [ "$swapLess" = true ]; then
      echo -e "g\nn\n\n\n${efiSize}\nn\n\n\n${rootSize}\nt\n1\n1\nw" | fdisk "$disk" >> log 2>&1
    else
      echo -e "g\nn\n\n\n${efiSize}\nn\n\n\n${swapSize}\nn\n\n\n${rootSize}\nt\n1\n1\nt\n2\n19\nw" | fdisk "$disk" >> log 2>&1
    fi
    echo -e "\n\e[32mRESULTS:\e[0m\n"
    fdisk -l "$disk" --color=always | grep -E -v -e '^Units' -e '^Sector size' -e '^I/O' -e '^Disk identifier'

    # filesystems
    efi=$(fdisk -l "$disk" | tail -n 3 | grep 'EFI System' | awk '{print $1}')
    [ "$swapLess" = true ] || swap=$(fdisk -l "$disk" | tail -n 3 | grep 'Linux swap' | awk '{print $1}')
    filesystem=$(fdisk -l "$disk" | tail -n 3 | grep 'Linux filesystem' | awk '{print $1}')
    read -p $'\nMake filesystems? (default=y): '
    if [ "$x" = e ] || [ "$x" = n ]; then echo -e '\nExiting...\n' && exit; fi
    if [[ "$x" = s ]]; then
        echo -e '\e[31mSkipped\e[0m\n'
    else
      echo 'Please wait a few minutes...'
      umount -l -q "$efi" "$filesystem"
      mkfs.fat -F32 "$efi" >> log 2>&1 || echo -e '\e[31mERROR: Failed to make filesystem for boot partition\e[0m'
      mkfs.ext4 "$filesystem" >> log 2>&1 || echo -e '\e[31mERROR: Failed to make filesystem for root partition\e[0m'
      mount "$filesystem" /mnt >> log 2>&1 || echo -e '\e[31mERROR: Failed to mount root partition\e[0m'
      if [ "$swapLess" != true ]; then
        mkswap "$swap" >> log 2>&1 || echo -e '\e[31mERROR: Failed to make swap partition\e[0m'
        swapon "$swap" >> log 2>&1 || echo -e '\e[31mERROR: Failed to activate swap partition\e[0m'
      fi
      echo -e 'Done\n'
    fi

    # pactrap
    read -p 'Install base packages? (default=y): ' x
    if [ "$x" = e ] || [ "$x" = n ]; then echo -e '\nExiting...\n' && exit; fi
    read -p 'Install zen kernel? (improved performance, higher power consumption) (default=y): ' x
    if [ "$x" = e ]; then
      echo -e '\nExiting...\n'
      exit
    elif [ "$x" = n ]; then
      echo 'Installing non-zen kernel...'
      kernel='linux'
    else
      kernel='linux-zen'
    fi

    echo -e '\n[1] AMD'
    echo '[2] Intel'
    echo '[n] None'
    read -p 'Please choose a microcode package: ' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    if [ "$x" = 1 ]; then
      microcode=amd-ucode
    elif [ "$x" = 2 ]; then
      microcode=intel-ucode
    else
      unset microcode
    fi

    sed -i 's:#ParallelDownloads:ParallelDownloads:' /etc/pacman.conf
    pacstrap /mnt base "$kernel" linux-firmware vim nano sudo "$microcode"
    genfstab -U /mnt >> /mnt/etc/fstab

    # chroot
    read -p $'\nChroot in? (default=y): ' x
    if [ "$x" = e ] || [ "$x" = n ]; then echo -e '\nExiting...\n' && exit; fi
    echo

  else

    diskSel

  fi

  # chroot
  mount "$filesystem" /mnt >> log 2>&1 || echo -e '\e[31mERROR: Failed to mount root partition\e[0m'
  mount --mkdir "$efi" /mnt/boot >> log 2>&1 || echo -e '\e[31mERROR: Failed to mount boot partition\e[0m'
  cp "$0" /mnt/root/install || echo -e '\e[31mERROR: Failed to copy install script to root partition\e[0m'
  chmod +x /mnt/root/install || echo -e '\e[31mERROR: Failed to make install script executable in root partition\e[0m'
  arch-chroot /mnt ./root/install
  rm -f /mnt/root/install /mnt/root/.efiDisk

  # reboot
  read -p $'\nReboot? (default=n): ' x
  [ "$x" = e ] && echo -e '\nExiting...\n' && exit
  if [ "$x" == y ]; then
    swapoff -a
    umount "$filesystem" "$efi" >> log 2>&1
    umount -R /mnt >> log 2>&1
    reboot
  fi
  echo 'echo Performing a clean exit...; swapoff -a; umount -R /mnt; sleep 1; reboot' > reboot
  chmod +x reboot
  echo -e "\n\e[32mScript finished!\e[0m"
  echo -e "Execute ./reboot for a clean exit\n"

elif [[ $(uname -a) =~ 'archiso' ]]; then # arch chroot

  # init
  echo -e "INFO: In chroot, you cannot CTRL+C\nTo exit, \e[31mDO NOT CTRL+Z or CTRL+D\e[0m (or it breaks)\nInstead, anwser 's' (skip) or 'e' (exit) to any question"

  # region
  while true; do
    echo
    ls /usr/share/zoneinfo/
    echo
    read -p 'Region? (default=Europe): ' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    [ "$x" = '' ] && x=Europe
    if [[ "$x" = s ]]; then
      echo -e "> \e[31mSkipped\e[0m"
      break
    elif [[ -d /usr/share/zoneinfo/"$x" && -n "$x" ]]; then
      echo -e "> \e[32mSelected $x\e[0m"
      break
    else
      echo -e '\n> \e[31mERROR: Invalid input\e[0m'
    fi
  done

  # city
  [ "$x" != s ] && \
  while true; do
    echo
    ls /usr/share/zoneinfo/"$x"
    echo
    read -p 'Location? (default=Paris): ' y
    [ "$y" = e ] && echo -e '\nExiting chroot...' && exit
    [ "$y" = '' ] && y=Paris
    if [[ "$y" = s ]]; then
      echo -e "> \e[31mSkipped\e[0m"
      break
    elif [[ -f /usr/share/zoneinfo/"$x"/"$y" ]]; then
      echo -e "> \e[32mSelected $y\e[0m"
      ln -sf /usr/share/zoneinfo/"$x"/"$y" /etc/localtime
      hwclock --systohc
      break
    else
      echo -e '\n> \e[31mERROR: Invalid input\e[0m'
    fi
  done

  # locale
  while true; do
    echo
    cat /etc/locale.gen | grep -E -o '[a-z]+_[A-Z]{2}' | sort | uniq | column
    echo
    read -p 'Locale? (default=en_US): ' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    [ "$x" = '' ] && x=en_US
    if [[ "$x" = s ]]; then
      echo -e "> \e[31mSkipped\e[0m\n"
      break
    elif [[ -n $(grep -E "^#$x" /etc/locale.gen) && "$x" =~ [a-z]+_[A-Z]{2} ]]; then
      selected=$(grep "^#$x" /etc/locale.gen | grep UTF | head -n 1)
      if [[ -f /etc/locale.gen.bak ]]; then
        cp /etc/locale.gen.bak /etc/locale.gen
      else
        cp /etc/locale.gen /etc/locale.gen.bak
      fi
      result=$(sed "s:$selected:${selected:1}:" /etc/locale.gen)
      echo "$result" >> /etc/locale.gen
      grep -E -o "^[a-z]+[A-Z]{2}" /etc/locale.gen
      locale-gen >> /root/log 2>&1
      echo -e "> \e[32mApplied $(sed 's:UTF-8 UTF-8:UTF-8:' <<< $(grep -E "^[a-z]+_[A-Z]{2}" /etc/locale.gen))\e[0m\n"
      break
    else
      echo -e '\n> \e[31mERROR: Invalid input\e[0m'
    fi
  done

  # keymap
  while true; do
    readarray -t rawKeymaps <<< $(find /usr/share/kbd/keymaps -type f -printf "%f\n")
    for i in "${rawKeymaps[@]}"; do
      allKeymaps+=("${i%%.*}");
      if [[ "${allKeymaps[@]: -1}" =~ ^[a-z]{2}$ ]]; then
        filteredKeymaps+=("${i%%.*}")
      fi
    done
    printf '%s\n' "${filteredKeymaps[@]}" | sort | uniq | column
    echo
    read -p 'Keymap? (default=fr) (more options=all): ' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    [ "$x" = all ] && printf '%s\n' "${allKeymaps[@]}" | sort | uniq | column | less && echo && continue
    [ "$x" = '' ] && x=fr
    if [[ "$x" = s ]]; then
      echo -e "> \e[31mSkipped\e[0m\n"
      break
    elif [[ -n $(printf '%s\n' "${allKeymaps[@]}" | grep -E '^'"$x"'$') ]]; then
      echo "KEYMAP=$x" > /etc/vconsole.conf
      echo -e "> \e[32mPermanent keymap set as $x\e[0m\n"
      break
    else
      echo -e '\n> \e[31mERROR: Invalid input\e[0m\n'
    fi
  done

  # hostname
  read -p 'Hostname? (default=arch): ' host
  [ "$host" = e ] && echo -e '\nExiting chroot...' && exit
  [ "$host" = '' ] && host=arch
  if [[ "$host" = s ]]; then
    echo -e "> \e[31mSkipped\e[0m"
  else
    echo "$host" > /etc/hostname
    echo -e "> \e[32mHostname set as $host\e[0m"
  fi

  # root pass
  read -p $'\nRoot password? (default=root): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  [ "$x" = '' ] && x=root
  if [[ "$x" = s ]]; then
    echo -e "> \e[31mSkipped\e[0m"
  else
    echo "root:$x" | chpasswd
    echo -e "> \e[32mPassword for "root" user set\e[0m"
  fi

  # user
  read -p $'\nUser name? (default=user): ' user
  [ "$user" = e ] && echo -e '\nExiting chroot...' && exit
  [ "$user" = '' ] && user=user
  if [[ "$user" = s ]]; then
    echo -e "> \e[31mSkipped\e[0m"
    user=user
  else
    useradd -m "$user" >> /root/log 2>&1 && \
    usermod -aG wheel "$user"
    echo -e "> \e[32mAdded user \"$user\"\e[0m"
  fi

  # user pass
  read -p $'\nUser password? (default=user): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  [ "$x" = '' ] && x=user
  if [[ "$x" = s ]]; then
    echo -e "> \e[31mSkipped\e[0m"
  else
    echo "$user:$x" | chpasswd
    echo -e "> \e[32mPassword for "$user" user set\e[0m"
  fi

  # auto login
  read -p $'\nAuto login? (default=y): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = y || -z "$x" ]]; then
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -o '-p -f -- \\\\\u' --noclear --autologin $(ls /home | head -n 1) - \$TERM" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
    echo -e "> \e[32mAuto login on for $(ls /home | head -n 1)\e[0m"
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # sudo
  read -p $'\nRequest password when user use sudo? (default=n): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = n || -z "$x" ]]; then
    echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo >> /root/log 2>&1
    echo -e "> \e[32mSettings saved\e[0m"
  elif [[ "$x" = y ]]; then
    echo '%wheel ALL=(ALL:ALL) ALL' | sudo EDITOR='tee -a' visudo >> /root/log 2>&1
    echo -e "> \e[32mSettings saved\e[0m"
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # hosts
  read -p $'\nAutoconfigure hosts file? (default=y): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = n ]]; then
    nano /etc/hosts
  elif [[ "$x" = y || -z "$x" ]]; then
    echo -e "127.0.0.1\tlocalhost" > /etc/hosts
    echo -e "::1\t\tlocalhost" >> /etc/hosts
    echo -e "127.0.1.1\t$user.localdomain\t$user" >> /etc/hosts
    echo -e "> \e[32mHosts file has been configured\e[0m\n"
  else
    echo -e "> \e[31mSkipped\e[0m\n"
  fi

  # boot manager
  echo -e '\n[1] GRUB'
  echo '[2] EFISTUB'
  echo '[n] None'
  read -p $'Please choose a bootloader: ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit

  unset flag
  if [ "$x" = 1 ]; then
    pacman -Sy grub os-prober --noconfirm || flag=true
    grub-install >> /root/log 2>&1 || flag=true
    grub-mkconfig -o /boot/grub/grub.cfg >> /root/log 2>&1 || flag=true
    if [ "$flag" = true ]; then
      echo -e "> \e[31mGRUB configuration failed\e[0m"
    else
      echo -e "> \e[32mGRUB was configured\e[0m"
    fi
  elif [ "$x" = 2 ]; then
    pacman -Sy efibootmgr --noconfirm || flag=true
    uuid="UUID=$(lsblk -f | grep '/$' | awk '{print $4}')"
    read -p 'Add silent boot kernel flags? (default=y)' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    [ "$x" != n ] && silent_flags='quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3'
    part="${efi##*[^0-9]}"
    disk="${efi::-${#part}}"
    pacman -Qqs '^linux-zen$' && kernel=linux-zen
    pacman -Qqs '^linux$' && kernel=linux
    ucode=$(find /boot -name '*-ucode.img' | head -n 1)
    if [ -n "$ucode" ]; then ucode="initrd=\\${ucode##*/}"
    else unset ucode; fi

    echo "COMMAND: efibootmgr --create --disk \"$disk\" --part \"$part\" --label \"Arch Linux\" --loader \"/vmlinuz-$kernel\" --unicode \"root=$uuid rw $ucode initrd=\initramfs-$kernel.img $silent_flags\""
    read -p 'Proceed? (default=y): ' x
    [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
    if [ "$x" != n ]; then
      efibootmgr --create --disk "$disk" --part "$part" --label "Arch Linux" --loader "/vmlinuz-$kernel" --unicode "root=$uuid rw $ucode initrd=\initramfs-$kernel.img $silent_flags"
      if [ "$?" = 0 ]; then
        echo -e "> \e[32mEFISTUB was configured\e[0m"
      else
        echo -e "> \e[31mEFISTUB configuration failed\e[0m"
      fi
    fi
  fi

  # packages
  base_packages='base-devel bc ffmpeg git htop jq lsof nano net-tools p7zip pv python python-pip screen sudo tree vim wget'
  extended_packages='arch-install-scripts cmake efibootmgr imagemagick jdk-openjdk mediainfo nvtop python-spotdl rtorrent yt-dlp'
  graphic_packages='bluez bluez-utils celluloid firefox grim kitty mpv nautilus noto-fonts-cjk pulseaudio pulseaudio-bluetooth pavucontrol slurp swaybg ttf-jetbrains-mono-nerd wl-clipboard'
  echo -e '\nPlease choose a package list:\n'
  echo "[1] Base (default): $base_packages"
  echo "[2] Extended: $extended_packages"
  echo "[3] Graphical: $graphic_packages"
  echo "[n] None"
  read -p $'\n> ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [ "$x" = 1 ] || [ -z "$x" ]; then
    pacman -Syu $base_packages
  elif [ "$x" = 2 ]; then
    pacman -Syu $base_packages $extended_packages
  elif [ "$x" = 3 ]; then
    pacman -Syu $base_packages $extended_packages $graphical_packages
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # backup
  read -p $'\nDownload and extract /home backup? (default=y): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if echo "$x" | grep -E -q '.{8,}'; then
    curl -#L '1o2.ir/bkp-prv' --http1.1 > backup.7z && \
    7z x backup.7z -o"/home/$(ls /home | head -n 1)" -p"$x" -y
  elif [[ "$x" = y || -z "$x" ]]; then
    curl -#L '1o2.ir/bkp-pub' --http1.1 > backup.7z && \
    7z x backup.7z -o"/home/$(ls /home | head -n 1)" -y
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi
  rm -rf backup.7z

  # desktop environment
  read -p $'\nInstall AMD drivers, Xorg, and Gnome? (default=y): ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = y || -z "$x" ]]; then
    pacman -Syu mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau xorg xorg-xinit gnome
    xinit="/home/$(ls /home | head -n 1)/.xinitrc"
    cat /etc/X11/xinit/xinitrc | head -n-5 > "$xinit"
    echo "gnome-session" >> "$xinit"
    systemctl enable gdm.service >> /root/log 2>&1
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # broadcom wifi drivers
  read -p $'\nSetup broadcom-wl-dkms driver? (default=y) ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = y || -z "$x" ]]; then
    pacman -Sy broadcom-wl-dkms
    rmmod b43 b43legacy ssb bcm43xx brcm80211 brcmfmac brcmsmac bcma wl >> /root/log 2>&1
    modprobe wl >> /root/log 2>&1
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # printing
  read -p $'\nSetup printing service? (default=y) ' x
  [ "$x" = e ] && echo -e '\nExiting chroot...' && exit
  if [[ "$x" = y || -z "$x" ]]; then
    pacman -Sy cups
    systemctl enable cups.service >> /root/log 2>&1
  else
    echo -e "> \e[31mSkipped\e[0m"
  fi

  # other
  systemctl enable NetworkManager >> /root/log 2>&1
  systemctl enable iwd >> /root/log 2>&1

  ## post install commands

  ## yay
  # sudo pacman -Sy go git
  # git clone --depth 1 https://aur.archlinux.org/yay-git.git
  # cd yay-git
  # makepkg -si
  # cd ..
  # rm -rf yay-git

  ## theming
  # yay -S gnome-browser-connector mutter-rounded materia-transparent-gtk-theme-git
  # sudo pacman -Sy gnome-tweaks grub-customizer
  # git clone --depth 1 https://github.com/vinceliuice/grub2-themes.git
  # cd grub2-themes/
  # sudo ./install.sh --theme stylish --screen ultrawide2k --icon white
  # cd ..
  # rm -rf grub2-themes/
  # sudo grub-customizer
  # sudo nano /etc/default/grub

  ## debloat
  # sudo rm -rf /usr/share/applications/lstopo.desktop /usr/share/applications/avahi-discover.desktop /usr/share/applications/vim.desktop /usr/share/applications/htop.desktop /usr/share/applications/bvnc.desktop /usr/share/applications/mpv.desktop /usr/share/applications/bssh.desktop /usr/share/applications/qvidcap.desktop /usr/share/applications/yelp.desktop /usr/share/applications/org.gnome.eog.desktop /usr/share/applications/org.gnome.Evince.desktop /usr/share/applications/org.gnome.Photos.desktop /usr/share/applications/org.gnome.FileRoller.desktop /usr/share/applications/qv4l2.desktop usr/share/applications/jconsole-java-openjdk.desktop usr/share/applications/jshell-java-openjdk.desktop
  # sudo pacman -R gnome-books gnome-clocks gnome-contacts gnome-logs gnome-maps cheese epiphany gnome-boxes gnome-font-viewer gnome-characters totem
  # sudo pacman -Rcns $(pacman -Qdtq)

  ## fonts
  # yay -S ttf-ms-fonts ttf-unifont

  ## spotdl + yt-dlp
  # pip install -U --force spotdl==4.0.0rc3


else

  echo 'Platform not supported'

fi

