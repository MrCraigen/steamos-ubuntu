#!/bin/bash

# Set the defaults. These can be overridden by specifying the value as an
# environment variable when running this script.
INCLUDE_OPENSSH="${INCLUDE_OPENSSH:-true}"
INCLUDE_SAKURA="${INCLUDE_SAKURA:-true}"
INCLUDE_PROTONFIX="${INCLUDE_PROTONFIX:-false}"
INCLUDE_DOSBOX="${INCLUDE_DOSBOX:-false}"
INCLUDE_D9VK="${INCLUDE_D9VK:-false}"
INCLUDE_GPU_DRIVERS="${INCLUDE_GPU_DRIVERS:-true}"
GPU_TYPE="${GPU_TYPE:-auto}"
PROTON_VERSION="${PROTON_VERSION:-none}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
STEAM_USER="${STEAM_USER:-steam}"
export STEAM_USER

# Configure the default versions of the SteamOS packages to use. These generally
# don't ever need to be overridden.
STEAMOS_COMPOSITOR_VER="${STEAMOS_COMPOSITOR_VER:-1.35+bsos1_amd64}"
STEAMOS_MODESWITCH_VER="${STEAMOS_MODESWITCH_VER:-1.10+bsos1_amd64}"
STEAMOS_PLYMOUTH_VER="${STEAMOS_PLYMOUTH_VER:-0.17+bsos2_all}"
STEAMOS_ALIENWAREWMI_VER="${STEAMOS_ALIENWAREWMI_VER:-2.58}"

# Ensure the script is being run as root
if [ "$EUID" -ne 0 ]; then
	echo "This script must be run with sudo."
	exit
fi

# Confirm from the user that it's OK to continue
if [[ "${NON_INTERACTIVE}" != "true" ]]; then
	echo "Options:"
	echo "  OpenSSH:                ${INCLUDE_OPENSSH}"
	echo "  Terminal:               ${INCLUDE_SAKURA}"
	echo "  Proton Fixes:           ${INCLUDE_PROTONFIX}"
	echo "  Dosbox:          				${INCLUDE_DOSBOX}"
	echo "  d9vk Support:          	${INCLUDE_D9VK}"
	echo "  GPU Drivers:            ${INCLUDE_GPU_DRIVERS}"
	echo "  GPU Type:               ${GPU_TYPE}"
	echo "  Steam User:             ${STEAM_USER}"
	echo ""
	echo "This script will configure a SteamOS-like experience on Ubuntu."
	read -p "Do you want to continue? [Yy] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "Starting installation..."
	else
		echo "Aborting installation."
		exit
	fi
fi

# Download the packages we need. If we fail at downloading, stop the script.
set -e
echo "Downloading SteamOS packages..."
wget "http://repo.steamstatic.com/steamos/pool/main/s/steamos-compositor/steamos-compositor_${STEAMOS_COMPOSITOR_VER}.deb"
wget "http://repo.steamstatic.com/steamos/pool/main/s/steamos-modeswitch-inhibitor/steamos-modeswitch-inhibitor_${STEAMOS_MODESWITCH_VER}.deb"
wget "http://repo.steamstatic.com/steamos/pool/main/p/plymouth-themes-steamos/plymouth-themes-steamos_${STEAMOS_PLYMOUTH_VER}.deb"
wget "http://repo.steamstatic.com/steamos/pool/main/s/steamos-base-files/steamos-base-files_${STEAMOS_ALIENWAREWMI_VER}.tar.xz"
set +e

# See if there is a 'steam' user account. If not, create it.
if ! grep "^${STEAM_USER}" /etc/passwd > /dev/null; then
	echo "Steam user '${STEAM_USER}' not found. Creating it..."
	adduser --disabled-password --gecos "" "${STEAM_USER}"
fi
STEAM_UID=$(grep "^${STEAM_USER}" /etc/passwd | cut -d':' -f3)
STEAM_GID=$(grep "^${STEAM_USER}" /etc/passwd | cut -d':' -f4)
echo "Steam user '${STEAM_USER}' found with UID ${STEAM_UID} and GID ${STEAM_GID}"

# Choosing from the guide in Proton (SteamPlay) Wiki https://github.com/ValveSoftware/Proton/wiki/Requirements
# Install the GPU drivers if it was specified by the user.
if [[ "${INCLUDE_GPU_DRIVERS}" == "true" ]]; then

	# Autodetect the GPU so we can install the appropriate drivers.
	if [[ "${GPU_TYPE}" == "auto" ]]; then
		echo "Auto-detecting GPU..."
		if lspci | grep -i vga | grep -iq nvidia; then
			echo "  Detected Nvidia GPU"
			GPU_TYPE="nvidia"
		elif lspci | grep -i vga | grep -iq amd; then
			echo "  Detected AMD GPU"
			GPU_TYPE="amd"
		elif lspci | grep -i vga | grep -iq intel; then
			GPU_TYPE="intel"
			echo "  Detected Intel GPU"
		else
			GPU_TYPE="none"
			echo "  Unable to determine GPU. Skipping driver install."
		fi
	fi

	# Install the GPU drivers.
	case "${GPU_TYPE}" in
		nvidia)
			echo "Installing the latest Nvidia drivers..."
			add-apt-repository ppa:graphics-drivers/ppa -y
			apt update
			apt install nvidia-driver-415 -y
			;;
		amd)
			echo "Installing the latest AMD drivers..."
			add-apt-repository ppa:oibaf/graphics-drivers -y
			apt update
			apt dist-upgrade -y

			dpkg --add-architecture i386
			apt update
			apt install mesa-vulkan-drivers mesa-vulkan-drivers:i386 -y
			;;
		intel)
			echo "Installing the latest mesa drivers..."
			add-apt-repository ppa:paulo-miguel-dias/pkppa -y
			apt update
			apt dist-upgrade -y

			dpkg --add-architecture i386
			apt update
			apt install mesa-vulkan-drivers mesa-vulkan-drivers:i386 -y
			;;
		none)
			echo "GPU not detected."
			;;
		*)
			echo "Skipping GPU driver installation."
			;;
	esac
fi

# Install steam and steam device support.
echo "Installing steam..."
apt update
apt install steam steam-devices x11-utils -y

# Enable Protonfix for ease of use with certain games that needs tweaking.
# https://github.com/simons-public/protonfixes
# Installing Protonfix for ease of use
if [[ "${INCLUDE_PROTONFIX}" == "true" ]]; then
	apt install python-pip python3-pip winetricks zenity -y
	echo "Installing protonfix..."
	sudo pip3 install git+https://github.com/simons-public/protonfixes@master
	# Installing cefpython3 for visual progress bar
	pip install cefpython3
fi

# Enable DOS Support for older games with Dosbox through SteamPlay
# https://github.com/dreamer/steam-dos
if [[ "${INCLUDE_DOSBOX}" == "true" ]]; then
	echo "Installing Dosbox..."
	apt install dosbox inotify-tools timidity fluid-soundfont-gm -y
fi

# Install a terminal emulator that can be added from Big Picture Mode.
if [[ "${INCLUDE_SAKURA}" == "true" ]]; then
	echo "Installing the sakura terminal emulator..."
	apt install sakura -y
fi

# Install openssh-server for remote administration
if [[ "${INCLUDE_OPENSSH}" == "true" ]]; then
	echo "Installing OpenSSH Server..."
	apt install openssh-server -y
fi

# Enable automatic login. We use 'envsubst' to replace the user with ${STEAM_USER}.
echo "Enabling automatic login..."
envsubst < ./conf/custom.conf > /etc/gdm3/custom.conf

# Create our session switching scripts to allow rebooting to the desktop
echo "Creating reboot to session scripts..."
envsubst < ./conf/reboot-to-desktop-mode.sh > /usr/local/sbin/reboot-to-desktop-mode
envsubst < ./conf/reboot-to-steamos-mode.sh > /usr/local/sbin/reboot-to-steamos-mode
chmod +x /usr/local/sbin/reboot-to-desktop-mode
chmod +x /usr/local/sbin/reboot-to-steamos-mode

# Create the "steamos-fg" script as a workaround for games like Deadcells with the Steam compositor.
cp ./conf/steamos-fg.sh /usr/local/sbin/steamos-fg
chmod +x /usr/local/sbin/steamos-fg

# Create a sudoers rule to allow passwordless reboots between sessions.
echo "Creating sudoers rules to allow rebooting between sessions..."
cp ./conf/reboot-sudoers.conf /etc/sudoers.d/steamos-reboot
chmod 440 /etc/sudoers.d/steamos-reboot

# Install the steamos compositor, modeswitch, and themes
echo "Configuring the SteamOS boot themes..."
dpkg -i ./*.deb &>/dev/null
apt install -f -y
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/steamos/steamos.plymouth 100
update-alternatives --set default.plymouth /usr/share/plymouth/themes/steamos/steamos.plymouth

# Update the grub theme.
echo 'GRUB_BACKGROUND=/usr/share/plymouth/themes/steamos/steamos_branded.png' | tee -a /etc/default/grub
update-grub

# Set the X session to use the installed steamos session
echo "Configuring the default session..."
cp ./conf/steam-session.conf "/var/lib/AccountsService/users/${STEAM_USER}"

# WIP - find a way to enable Steamplay without using Desktop Steam Client. Also maybe find a way to enable Steam Beta with latest Steamplay
# Enable SteamPlay
echo "Enable Steamplay..."
echo "Starting Steam to create initial configurations."
echo "Close steam to continue."
sudo STEAM_USER=${STEAM_USER} ./run_steam.sh

echo "Set Steamplay (Proton) version..."
sed -i 's/\("enable"\).*/\1 "1"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
echo "Choose Steamplay version:"
echo "1) Proton 3.7"
echo "2) Proton 3.7 Beta"
echo "3) Proton 3.16"
echo "4) Proton 3.16 Beta"
echo "5) Proton 4.2 (Recommended)"
read case;

case $case in
	1)
		PROTON_VERSION="Proton 3.7"
		sed -i 's/\("name"\).*/\1 "proton_37"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
		;;
	2)
		PROTON_VERSION="Proton 3.7 Beta"
		sed -i 's/\("name"\).*/\1 "proton_37_beta"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
		;;
	3)
		PROTON_VERSION="Proton 3.16"
		sed -i 's/\("name"\).*/\1 "proton_316"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
		;;
	4)
		PROTON_VERSION="Proton 3.16 Beta"
		sed -i 's/\("name"\).*/\1 "proton_316_beta"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
		;;
	5)
		PROTON_VERSION="Proton 4.2"
		sed -i 's/\("name"\).*/\1 "proton_42"/' /home/${STEAM_USER}/.steam/steam/config/config.vdf
		;;
esac


if [[ "${INCLUDE_PROTONFIX}" == "true" ]]; then
	# Enable Protonfix
	echo "import protonfixes" | tee -a /home/${STEAM_USER}/.steam/steam/steamapps/common/${PROTON_VERSION}/user_settings.py
fi

if [[ "${INCLUDE_D9VK}" == "true" ]]; then
	# Enable d9vk
	cd /home/${STEAM_USER}/.steam/steam/steamapps/common/${PROTON_VERSION}/dist/
	# Downloading latest alpha release
	wget https://github.com/Joshua-Ashton/d9vk/releases/download/0.12/d9vk-0.12.tar.gz
	tar -zxvf d9vk-0.12.tar.gz root/x32/ -C /home/${STEAM_USER}/.steam/steam/steamapps/common/${PROTON_VERSION}/dist/lib/wine/dxvk/
	tar -zxvf d9vk-0.12.tar.gz root/x64/ -C /home/${STEAM_USER}/.steam/steam/steamapps/common/${PROTON_VERSION}/dist/lib64/wine/dxvk/
fi

if [[ "${INCLUDE_DOSBOX}" == "true" ]]; then
	# Add steam-dos as a Proton version
	cd /home/${STEAM_USER}/.steam/root/compatibilitytools.d/
	curl -L https://github.com/dreamer/steam-dos/releases/download/v0.3.0/steam-dos.tar.xz | tar xJf -
fi

echo ""
echo "Installation complete! Press ENTER to reboot or CTRL+C to exit"
read -r
reboot
