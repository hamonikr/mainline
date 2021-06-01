# mainline 우분투 커널 업그레이드 도구

이 프로그램은 `sudo apt upgrade` 를 통해 제공되지 않는 특정 버전 또는 최신 커널을 사용하고 싶은 경우
터미널을 사용하지 않고 GUI 를 통한 손쉬운 커널 업그레이드를 제공하는 프로그램 입니다.

 * upstream : https://github.com/bkw777/mainline
 * latest version : 1.0.14

![Main window screenshot](main_window_ko.png)

# 프로그램 설치

## 하모니카 사용자 (하모니카 3.0 이상)
```
sudo apt update
sudo apt install mainline
```

## Ubuntu, LinuxMint (>=Ubuntu 18.04)
```
wget -qO- https://pkg.hamonikr.org/add-hamonikr.apt | sudo -E bash -
sudo apt install mainline
```

### Build & Test
	sudo apt install libgee-0.8-dev libjson-glib-dev libvte-2.91-dev valac aria2 lsb-release aptitude

	git clone https://github.com/bkw777/mainline.git
	
	cd mainline
	make
	sudo make install

### About
mainline is a fork of [ukuu](https://github.com/teejee2008/ukuu)

The original author stopped maintaining the original GPL version of ukuu and switched to a [paid license](https://teejeetech.in/tag/ukuu/) for future versions.

