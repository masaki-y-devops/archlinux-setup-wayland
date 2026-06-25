#!/usr/bin/env bash

## 最低限のエラーハンドリング
set -e

## 一時ディレクトリを指定
TMP=~

## bootstrapのtarballを取得するサーバーを指定
MAINSRV=https://fastly.mirror.pkgbuild.com
SUBSRV=https://mirror.rackspace.com

## ユーザー名と初期パスワードを指定。
## インストール後に必ず変更する
USERNAME=archuser
USERPASS=initpass
ROOTPASS=initpassroot

## CPUメーカーを特定
echo "Setting CPU vendor..."
VENDORID=$(lscpu | grep "Vendor ID:" | awk '{print $3}')
if [ "${VENDORID}" = "GenuineIntel" ]; then
    CPU=intel
else
    CPU=amd
fi
echo "CPU vendor is ${CPU}."

## GPUメーカーを特定
## 優先度: nvidia > ati > amdgpu > intel
echo "Setting VGA vendor..."
if [ "$(lspci | grep VGA | grep -o NVIDIA)" = "NVIDIA" ]; then
	VGA=nvidia
elif [ "$(lspci | grep VGA | grep -o ATI)" = "ATI" ]; then
	VGA=ati
elif [ "$(lspci | grep VGA | grep -o AMD)" = "AMD" ]; then
	VGA=amdgpu
else
	VGA=intel
fi
echo "VGA vendor is ${VGA}."

## eMMC/nvmeデバイスの場合、メインストレージのデバイス名がぶれるため判定
echo "Setting target block device..."
DISK=$(lsblk | grep -E "8:0|179:0|259:0" | awk '!/part|run/ {print $1}')

## nvme
if [[ "${DISK}" =~ "nvme0n1" ]]; then
        DISK=nvme0n1
elif [[ "${DISK}" =~ "nvme1n1" ]]; then
        DISK=nvme1n1
else
        :
fi

## emmc
if [[ "${DISK}" =~ "mmcblk0" ]]; then
        DISK=mmcblk0
elif [[ "${DISK}" =~ "mmcblk1" ]]; then
        DISK=mmcblk1
else
        :
fi
echo "Target System Drive: ${DISK}."

## パーティション名を設定
## sda1/mmcblk{0,1}p1/nvme{0,1}n1p1 : bootパーティション用
## sda2/mmcblk{0,1}p2/nvme{0,1}n1p2 : rootパーティション用
echo "Setting partition name..."
if [ "${DISK}" = "mmcblk0" ] || [ "${DISK}" = "mmcblk1" ]; then
        DISK1=${DISK}p1
        DISK2=${DISK}p2
elif [ "${DISK}" = "nvme0n1" ] || [ "${DISK}" = "nvme1n1" ]; then
        DISK1=${DISK}p1
        DISK2=${DISK}p2
else
        DISK1=${DISK}1
        DISK2=${DISK}2
fi
echo "Target partition: ${DISK1} and ${DISK2}."

## インストール用一時環境の構築
## pacstrapを利用可能にする
## ライブ環境の差異を吸収するためでもある
echo "Building temporary installation environment..."

## bootstrap用のtarballの取得
## メインサーバから取得できない場合はサブサーバーから取得、それでも失敗すれば終了ステータス1を返して落ちる
echo "Downloading tarball..."
if curl --output-dir ${TMP} --remote-name-all ${MAINSRV}/iso/latest/{archlinux-bootstrap-x86_64.tar.zst,sha256sums.txt}; then
	echo "Bootstrap tarball downloaded: ${MAINSRV}."
else
	if curl --output-dir ${TMP} --remote-name-all ${SUBSRV}/iso/latest/{archlinux-bootstrap-x86_64.tar.zst,sha256sums.txt}; then
		echo "Bootstrap tarball downloaded: ${SUBSRV}."
	else
		echo "FAILED: Downloading bootstrap" >&2
		read -rp "Press enter to exit."
		exit 1
	fi
fi

## GPG署名ファイルを取得
echo "Downloading signature file from archlinux.org..."
curl --output-dir ${TMP} -O https://archlinux.org/iso/latest/archlinux-bootstrap-x86_64.tar.zst.sig

## GPG検証
gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.org
VERIFY=$(gpg --keyserver-options auto-key-retrieve --verify ${TMP}/archlinux-bootstrap-x86_64.tar.zst.sig ${TMP}/archlinux-bootstrap-x86_64.tar.zst 2>&1 | grep "Good" | awk '{print $2}')
if [ "${VERIFY}" = "Good" ]; then
    echo "Verification OK."
else
    echo "Verification failed. Stopped."
    read -rp "Press enter to exit."
	exit 1
fi

## チェックサム
echo "Verifying tarball..."
CHECKSUM=$(sha256sum -c ${TMP}/sha256sums.txt 2>&1 | grep OK | awk '{print $2}')
if [ "${CHECKSUM}" = "OK" ]; then
    echo "Checksum OK."
else
    echo "FAILED: Verifying bootstrap tarball checksum failed." >&2
    read -rp "Press enter to exit."
	exit 1
fi

## tarballを展開
echo "Unpacking tarball..."
sudo tar xvf ${TMP}/archlinux-bootstrap-x86_64.tar.zst -C ${TMP} --numeric-owner

## mirrorlistを編集
echo "Setting tmp pacman configuration..."
cat << MIRRORLIST | sudo tee ${TMP}/root.x86_64/etc/pacman.d/mirrorlist
Server = ${MAINSRV}/\$repo/os/\$arch
Server = ${SUBSRV}/\$repo/os/\$arch
MIRRORLIST

## pacmanの並列ダウンロードを有効化
sudo sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/g' ${TMP}/root.x86_64/etc/pacman.conf

## システムファイルのマウント
echo "Mounting tmp environment..."
sudo mount --rbind ${TMP}/root.x86_64 ${TMP}/root.x86_64
sudo mount -t proc /proc ${TMP}/root.x86_64/proc
sudo mount -t sysfs /sys ${TMP}/root.x86_64/sys
sudo mount --rbind /dev ${TMP}/root.x86_64/dev
sudo mount --rbind /run ${TMP}/root.x86_64/run
sudo mount --make-rslave ${TMP}/root.x86_64/sys
sudo mount --make-rslave ${TMP}/root.x86_64/dev
sudo mount --make-rslave ${TMP}/root.x86_64/run
sudo mount --bind /sys/firmware/efi/efivars ${TMP}/root.x86_64/sys/firmware/efi/efivars

## 名前解決のため、ライブ環境のresolv.confを一時環境にコピーする
echo "Copying resolv.conf to tmp environment..."
sudo cp -L /etc/resolv.conf ${TMP}/root.x86_64/etc/resolv.conf

## 一時環境の構築をchrootで実行し、/mnt以下に最小環境をインストールしておく
cat <<-INITENV | sudo chroot ${TMP}/root.x86_64
	pacman-key --init
	pacman-key --populate
	pacman -Syu --noconfirm
	pacman -S --noconfirm parted dosfstools efibootmgr

	## Cleaning unused uefi nvram entries if it exists
	EFIENTRY=$(efibootmgr -v | grep -E "^Boot00[0-9][0-9]*" | grep -v UEFI | awk '{print $1}' | cut -b 5-8 | xargs)
	if [[ -n "${EFIENTRY}" ]]; then
		for i in ${EFIENTRY}; do
			efibootmgr -b "${i}" -B
		done
		echo "EFI entries are deleted."
	else
		echo "No EFI entries."
	fi

	## Perform Partitoning
	parted -s /dev/${DISK} mklabel gpt
	parted -s /dev/${DISK} mkpart "esp" fat32 1MiB 513MB
	parted -s /dev/${DISK} set 1 esp on
	parted -s /dev/${DISK} mkpart "root" ext4 513MB 100%

	## Create filesystem
	yes | mkfs.vfat -F32 /dev/${DISK1}
	yes | mkfs.ext4 /dev/${DISK2}

	## Mounting partitions
	mount /dev/${DISK2} /mnt
	mkdir /mnt/boot
	mount /dev/${DISK1} /mnt/boot

	## Installing base system
	pacstrap /mnt base linux{,-firmware} ${CPU}-ucode efibootmgr sudo iwd

	## Generating fstab
	cat <<-FSTAB > /mnt/etc/fstab
		/dev/disk/by-partlabel/root / ext4 defaults 0 1
		/dev/disk/by-partlabel/esp /boot vfat defaults 0 2
	FSTAB
INITENV

## 一時環境構築を終えてchrootを抜けた後、ターゲットとなるディスクをマウント
echo "Mounting /mnt again..."
sudo mount "/dev/${DISK2}" /mnt
sudo mount "/dev/${DISK1}" /mnt/boot
sudo mount -t proc /proc /mnt/proc
sudo mount -t sysfs /sys /mnt/sys
sudo mount --rbind /dev /mnt/dev
sudo mount --rbind /run /mnt/run
sudo mount --make-rslave /mnt/sys
sudo mount --make-rslave /mnt/dev
sudo mount --make-rslave /mnt/run
sudo mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

## resolv.confを新環境にコピー（pacmanを実行するため）
sudo cp -L /etc/resolv.conf /mnt/etc/resolv.conf

## 新環境のmirrorlist設定
cat << MIRRORLIST | sudo tee /mnt/etc/pacman.d/mirrorlist
Server = ${MAINSRV}/\$repo/os/\$arch
Server = ${SUBSRV}/\$repo/os/\$arch
MIRRORLIST

## 新環境のpacman並列ダウンロード設定
sudo sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf

## 新環境にchrootして必要な設定を行う
cat <<-INITSETUP | sudo chroot /mnt
	## ロケール設定
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf

	## 一時パスワード（捨てパスワード）設定する
	## 初回起動時に「必ず」変更する
	echo -e "${ROOTPASS}\n${ROOTPASS}" | passwd
	useradd -m -g wheel ${USERNAME}
	echo -e "${USERPASS}\n${USERPASS}" | passwd ${USERNAME}

	## sudo設定。/etc/sudoersにユーザーを追加する
	echo '${USERNAME} ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo
	
	## ブートローダ(EFIstub)をセットアップ
	## バックライト問題修正のため、Intel Atom Z8750デバイス(GPD WIN1,Pocket1)などの場合、
	## カーネルパラメータおよびカーネルモジュールを追加してinitramfsを再ビルド
	if [ $(lscpu | grep "Model name" | grep -o "Z8750") = "Z8750" ]; then
		efibootmgr \
		-c -g -d /dev/${DISK} \
		-p 1 -L "archlinux" -l /vmlinuz-linux \
		-u 'root=PARTLABEL=root rw initrd=${CPU}-ucode.img initrd=initramfs-linux.img quiet \
		dmi_product_name=GPD-WINI55 acpi_vendor=native'
		sed -i 's/MODULES=()/MODULES=(pwm-lpss pwm-lpss-platform)/' /etc/mkinitcpio.conf
		mkinitcpio -p linux
	else
		efibootmgr \
		-c -g -d /dev/${DISK} \
		-p 1 -L "archlinux" -l /vmlinuz-linux \
		-u 'root=PARTLABEL=root rw initrd=${CPU}-ucode.img initrd=initramfs-linux.img quiet'
	fi

	## DHCPを使用する簡易な設定をsystemd-networkdに追加
	## 無線LAN
	cat <<-WLAN > /etc/systemd/network/25-wl.network
		[Match]
		Name=wl*

		[Network]
		DHCP=yes
	WLAN

	# イーサネット
	cat <<-ETH > /etc/systemd/network/30-en.network
		[Match]
		Name=en*

		[Network]
		DHCP=yes
	ETH

	## DNSサーバー設定
	## サーバーは任意
	## Google:		8.8.8.8, 8.8.4.4
	## Cloudflare:	1.1.1.1, 1.0.0.1
	## AdGuard:		94.140.14.14, 94.140.14.14
	cat <<-RESOLVCONF > /etc/resolv.conf
		nameserver 94.140.14.14
		nameserver 94.140.15.15
	RESOLVCONF

	## systemdサービス自動起動を有効化
	systemctl enable systemd-networkd iwd

	## GUI環境や必須アプリをインストール
	pacman -S --noconfirm wayland seatd wlr-randr sway i3status pulseaudio \
	otf-ipafont ttf-ubuntu-font-family fcitx5{,-gtk,-qt,-mozc,-configtool} kwindowsystem \
	nano swaybg wofi firefox lxterminal thunar gvfs

	## Waylandを想定したドライバインストール
	if [ "${VGA}" = "nvidia" ]; then
		pacman -S --noconfirm mesa
	elif [ "${VGA}" = "ati" ]; then
		:
	elif [ "${VGA}" = "amdgpu" ]; then
		:
	else
		pacman -S --noconfirm mesa
	fi

	## sway関連でseatdが必要
	usermod -aG seat ${USERNAME}
	systemctl enable seatd

	## TPM関連のエラーを抑止
	systemctl mask dev-tpmrm0.device

	## ユーザーをvideoグループに追加(バックライト調整関連で必須)
	gpasswd -a ${USERNAME} video
INITSETUP

## 起動時の致命的でないエラーメッセージを抑制
cat << 'PRINTK' | sudo tee /mnt/etc/sysctl.d/20-quiet-printk.conf
	kernel.printk = 3 3 3 3
PRINTK
	
## ユーザー権限でUMPCの内蔵ディスプレイのバックライト調整ができるように、udevルールを追加
cat <<-'UDEV' | sudo tee /mnt/etc/udev/rules.d/backlight.rules
	ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video $sys$devpath/brightness", RUN+="/bin/chmod g+w $sys$devpath/brightness"
UDEV
	
## Intel HD Audioカーネルモジュールの設定変更
## OS終了後、電源オフ時に盛大なポップノイズが出ることを防ぐ
cat <<-FIXNOISE | sudo tee /mnt/etc/modprobe.d/snd-hda-intel.conf
	options snd_hda_intel power_save=0
FIXNOISE

## Sway設定を新環境に書き込み
sudo mkdir -p /mnt/home/${USERNAME}/.config/{sway,i3status}

cat << 'SWAYCONFIG' | sudo tee /mnt/home/${USERNAME}/.config/sway/config
# i3 config file (v4)

## fonts 
font pango:Ubuntu Regular 13

## i3status
bar {
 status_command i3status
 position top
 tray_output none
 colors {
  focused_workspace  #000000 #000000 #ffffff
  active_workspace   #000000 #000000 #ffffff
  inactive_workspace #000000 #000000 #666666
  }
}

## variables
## Mod1 is Alt key
## Mod4 is Win key
set $mod Mod4
set $nsi --no-startup-id
set $ws workspace
set $mc move container to workspace

## keybinds
## apps
bindsym $mod+Return exec $nsi wofi --show run
bindsym $mod+BackSpace kill
bindsym $mod+f exec $nsi firefox
bindsym $mod+l exec $nsi lxterminal

## volumes
bindsym XF86AudioMute exec $nsi pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86AudioRaiseVolume exec $nsi pactl set-sink-volume @DEFAULT_SINK@ +1%
bindsym XF86AudioLowerVolume exec $nsi pactl set-sink-volume @DEFAULT_SINK@ -1%
bindsym F2 exec $nsi pactl set-sink-volume @DEFAULT_SINK@ +1%
bindsym F1 exec $nsi pactl set-sink-volume @DEFAULT_SINK@ -1%

## brightness
bindsym $mod+d exec $nsi echo `expr $(cat /sys/class/backlight/intel_backlight/brightness) - 1` > /sys/class/backlight/intel_backlight/brightness
bindsym $mod+u exec $nsi echo `expr $(cat /sys/class/backlight/intel_backlight/brightness) + 1` > /sys/class/backlight/intel_backlight/brightness

## workspaces
bindsym $mod+1 $ws 1
bindsym $mod+2 $ws 2
bindsym $mod+3 $ws 3
bindsym $mod+q $mc 1; $ws 1
bindsym $mod+w $mc 2; $ws 2
bindsym $mod+e $mc 3; $ws 3

## autostart
exec $nsi fcitx5
exec $nsi swaybg -i ~/Wallpapers/wallpaper.jpg

## display scaling
## To detect display name, use "swaymsg -t get_outputs"
## set 1.5 for GPD Pocket1
output DSI-1 scale 1.0

## window border settings
default_border pixel 0

## window floating settings
## to get app_id or instance or class, use "swaymsg -t get_tree"
floating_maximum_size 960 x 540
for_window [floating] move position center

for_window [window_role="dialog"] floating enable
for_window [window_role="pop-up"] floating enable
for_window [window_role="bubble"] floating enable
for_window [window_role="task_dialog"] floating enable
for_window [window_role="menu"] floating enable

for_window [title="^Settings$"] floating enable
for_window [title="^Preferences$"] floating enable
for_window [title="^Settings$"] floating enable

for_window [title="^About Mozilla Firefox$" app_id="firefox"] floating enable
for_window [title="Extension:" app_id="firefox"] floating enable
for_window [app_id="com.nextcloud.desktopclient.nextcloud"] floating enable
for_window [instance="org.cryptomator.launcher.Cryptomator"] floating enable
SWAYCONFIG

cat << I3STCONFIG | sudo tee /mnt/home/${USERNAME}/.config/i3status/config
general {
 colors = false
 }

order += "volume master"
order += "ethernet _first_"
order += "wireless wlan0"
order += "battery 0"
order += "time"

volume master {
 format = "VOL.%volume"
 format_muted = "VOL.muted"
 device = "default"
 mixer = "Master"
 mixer_idx = 0
 }

ethernet _first_ {
 format_up = "Ethernet"
 format_down = ""
}

wireless wlan0 {
 format_up = "%essid"
 format_down = "No connection"
 }

battery 0 {
 format = "%percentage %status"
 last_full_capacity = true
 format_percentage = "%.00f%s"
 ## this is for GPD Win1 or Pocket1
 ## path = "/sys/class/power_supply/max170xx_battery/uevent"
 }

time {
 format = "%Y/%m/%d %H:%M"
}
I3STCONFIG

## コンソールログインでsway起動（ディスプレイマネージャなしの構成）
cat << BASHPROFILE | sudo tee /mnt/home/${USERNAME}/.bash_profile
exec sway
BASHPROFILE

## 新環境のホームディレクトリの権限修正
## ユーザー権限でdotfilesが読み込めずPulseAudioなども動作しない
cat << FIXUSRDIR | sudo chroot /mnt
chown -R ${USERNAME}: /home/${USERNAME}
FIXUSRDIR
         
echo "Installation completed. Reboot."
