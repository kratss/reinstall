#!/usr/bin/env fish
# vim:foldmethod=marker:foldmarker=###,##

# OPTIONS
# --apps: Install favorite apps
# --type=: Specify the desired installation type
#   headless: config for headless installs
#   gui: setup my preferred graphical environment
#   all: everything needed for my main personal computer setup
# --extras: add full multimedia support
#  
# TODO: Automate adding matrix-ansible update script to crontab or systemd
# TODO: Systemd service to run `updatedb` daily
# TODO: Use flatpak-create-usb for enabling local installation w/o internet
# TODO: Add flathub remote, possibly automate enabling flatpaks
# TODO: include flatpaks: flatseal, authenticator, qbittorrent, dejadup, krita
# TODO: configure firefox:
#   Create a profile: .mozilla/firefox/sway/ or 
#   	snap/firefox/common/.mozilla/firefox/sway/
#   Copy over ./extensions/ ./chrome/ ./prefs.js ./home.html
# TODO: sed edit foot.ini so the foot-extra is specified correcily for each distro
# TODO: Add ~/.config/tridactyl to dotfiles repo

argparse apps extras 'type=?' -- $argv
or return 1

### Packages
# Basics are commonly installed utilities that may be missing on minimal installs
# Separated to reduce clutter
set headless_basics \
    encfs \
    plocate

set headless \
    $headless_basics \
    curl \
    fish \
    fuzzel \
    fzf \
    git \
    htop \
    nmtui \
    nnn \
    neovim \
    trash-cli \
    w3m \
    wl-clipboard

set gui_basics bluez

set gui \
    $gui_basics \
    copyq \
    foot \
    fuzzel \
    grimshot \
    helvum \
    imv \
    light \
    mpv \
    mullvad-vpn \
    mullvad-browser \
    sway \
    tlp \
    waybar \
    wlsunset

set apps \
    firefox \
    keepassxc \
    newsboat \
    thunderbird

set extras

set matrix_admin \
    ansible \
    just

set lazyvim \
    luarocks \
    fd-find

if test "$_flag_type" = headless
    set -g packages $headless $lazyvim
end

if test "$_flag_type" = gui
    set -g packages $headless $gui
end

if test "$_flag_type" = all
    set -g packages $headless $gui $apps $extras
    set -g flatpaks
    set -g groups Multimedia
end
##
### Package manager detection
# Also handles varying package names across distros
if type dnf 2>/dev/null
    set -g mngr dnf
    set -g group "group install"
    set -a gui foot-terminfo
else if type apt 2>/dev/null
    set -g mngr apt-get
    set packages (string replace nmtui "" $packages)
else if type zypper 2>/dev/null
    set -g mngr zypper
    set -g group "install -t pattern"
    set packages (string replace nmtui      NetworkManager-tui $packages)
    set packages (string replace foot-extra foot-extra-terminfo $packages)
else
    echo "Failed to detect package manager."
    exit
end
echo ""
echo "Detected package manager: $mngr"
echo "Installing script dependencies"
sudo $mngr install git curl
sudo $mngr update
##
### Repo: Mullvad
if contains mullvad-vpn $packages || or contains mullvad-browser $packages
    echo ""
    echo "Enabling Mullvad repo"
    if test "$mngr" = dnf
        sudo dnf config-manager --add-repo \
            https://repository.mullvad.net/rpm/stable/mullvad.repo
    else if test "$mngr" = apt-get
        sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc \
            https://repository.mullvad.net/deb/mullvad-keyring.asc
        echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc \
            arch=$( dpkg --print-architecture )] \
            https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/mullvad.list
        sudo apt-get update
    else if test "$mngr" = zypper
        sudo zypper addrepo -f https://repository.mullvad.net/rpm/stable/mullvad.repo
    else
        echo "ERROR: Unable to enable Mullvad repo"
    end
end
##
### Repo: :
### Installation
echo ""
echo "Installing packages"
sudo $mngr install $packages
echo ""
echo "Installing dot files"
if test -e ./dotfiles
    git clone https://codeberg.org/krats/dotfiles
    mkdir ~/.config 2>/dev/null
    mkdir ~/.local/bin 2>/dev/null
    cp -r ./dotfiles/.config/* ~/.config/
    #cp -r ./dotfiles/.local/bin/* ~/.local/bin/
    rm -r -f ./dotfiles
end
##
### Systemctl
echo ""

# Syncthing
if contains syncthing $packages
    echo "Enabling syncthing.service"
    systemctl --user enable syncthing.service
    systemctl --user start syncthing.service
    systemctl --user status syncthing.service | head -n 3
end

# Bluetooth
if contains bluez $packages
    echo "Enabling bluetooth.service"
    systemctl enable bluetooth.service
    systemctl start bluetooth.service
    systemctl status bluetooth.service | head -n 3
end

# Matrix server updater
if contains all $packages
    echo "Enabling matrix-updater.service"
    systemctl --user enable matrix-updater.serivce
    systemctl --user status matrix-updater.service | head -n 3
end
##
