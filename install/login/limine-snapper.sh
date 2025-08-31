#!/bin/bash

if command -v limine &>/dev/null; then
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF

  [[ -f /boot/EFI/limine/limine.conf ]] && EFI=true

  # Conf location is different between EFI and BIOS
  [[ -n "$EFI" ]] && limine_config="/boot/EFI/limine/limine.conf" || limine_config="/boot/limine/limine.conf"

  CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

  sudo tee /etc/default/limine <<EOF >/dev/null
TARGET_OS_NAME="Arch Linux"

ESP_PATH="/boot"

KERNEL_CMDLINE[default]="$CMDLINE"
KERNEL_CMDLINE[default]+="quiet splash"

ENABLE_UKI=yes

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"

MAX_SNAPSHOT_ENTRIES=5

SNAPSHOT_FORMAT_CHOICE=5
EOF

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # We overwrite the whole thing knowing the limine-update will add the entries for us
  sudo tee /boot/limine.conf <<EOF >/dev/null
### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
timeout: 3
default_entry: 1
wallpaper: boot():/boot.jpg
 
EOF

  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook
  sudo limine-update

  # Match Snapper configs if not installing from the ISO
  if [ -z "${OMARCHY_CHROOT_INSTALL:-}" ]; then
    if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
      sudo snapper -c root create-config /
    fi

    if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
      sudo snapper -c home create-config /home
    fi
  fi

  # Tweak default Snapper configs
  sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}

  chrootable_systemctl_enable limine-snapper-sync.service
fi

 sudo cp ~/.local/share/omarchy/boot.jpg /boot/boot.jpg
 sudo cp ~/.local/share/omarchy/bash_profile ~/.bash_profile

# Add UKI entry to UEFI machines to skip bootloader showing on normal boot
if [ -n "$EFI" ] && efibootmgr &>/dev/null && ! efibootmgr | grep -q Omarchy &&
  ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "American Megatrends"; then
  sudo efibootmgr --create \
    --disk "$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]*$//')" \
    --part "$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]*$' | sed 's/^p//')" \
    --label "Omarchy" \
    --loader "\\EFI\\Linux\\$(cat /etc/machine-id)_linux.efi"
fi
