## これは何？

[Arch Linux](https://archlinux.org)の自動インストールスクリプト。

Xorg(i3wm)での構築はこちら→[arch-setup-xorg](https://github.com/masaki-y-devops/archlinux-setup-xorg)

## 使用例

~~~bash

git clone https://github.com/masaki-y-devops/archlinux-setup-wayland

cd ./archlinux-setup-wayland

chmod +x ./install.sh

./install.sh

~~~

## こだわりポイント

### EFISTUB

[GRUB](https://wiki.archlinux.jp/index.php/GRUB)や[systemd-boot](https://wiki.archlinux.jp/index.php/Systemd-boot)から、徐々にステップアップしていき、できるだけ起動速度を早められないか？を試行錯誤するのを楽しめた。

古いLegacy BIOSマシンであればGRUBを選択することになるが、流石に古すぎる&軽い運用でもストレスが溜まってきていたので売却し、手元のマシンはUEFIのものだけになったので、BIOSサポートをやめて構築。

### systemd-networkd + iwd(iwctl)

当初[NetworkManager](https://wiki.archlinux.jp/index.php/NetworkManager)を使用していたが、

**「Wi-Fiにつなげられさえすれば、軽量なプロセスがいい」**

と思い立ち、ネットワーク周りの勉強も兼ね、試行錯誤してみた。

オーソドックスな設定ではあるが、DHCP設定、``/etc/resolv.conf``のDNS周りなど、少しは勉強になった。

### ディスプレイマネージャーなし、Swayで構築

個人的な運用上、画面の小さいUMPCでは、ほぼアプリを全画面か左右分割でしか使っていないことに気づいたので、

タイル型ウインドウマネージャーを使い始めた。結果としては上部にバッテリー残量や時計、ネットワーク接続状況、音量などが表示されていれば全く問題なかった。

基本スタック型なWindowsとの差別化としても有益だと思う。

メインはデスクトップPCでWindowsを使用しているので、気分を変えてUMPCでのブラウジングも中々いいです。

## 参考文献

[パフォーマンスの向上/ブートプロセス - ArchWiki](https://wiki.archlinux.jp/index.php/%E3%83%91%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%B3%E3%82%B9%E3%81%AE%E5%90%91%E4%B8%8A/%E3%83%96%E3%83%BC%E3%83%88%E3%83%97%E3%83%AD%E3%82%BB%E3%82%B9)
