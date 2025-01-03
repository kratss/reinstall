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
# TODO: Use flatpak-create-usb for enabling local installation w/o internet
# TODO: Add flathub remote, possibly automate enabling flatpaks
# TODO: include flatpaks: flatseal, authenticator, qbittorrent, dejadup, krita
# TODO: configure firefox:
#   Create a profile: .mozilla/firefox/sway/ or 
#   	snap/firefox/common/.mozilla/firefox/sway/
#   Copy over ./extensions/ ./chrome/ ./prefs.js ./home.html
# TODO: sed edit foot.ini so the foot-extra is specified correcily for each distro

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
    gitui \
    htop \
    NetworkManager-tui \
    neovim \
    ranger \
    trash-cli \
    tree \
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
    qutebrowser \
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
    fd-find \
    fuse

echo "Installation type is:"
echo $_flag_type

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
    set packages (string replace NetworkManager-tui "" $packages)
    set packages (string replace gitui "git-gui" $packages)
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
### Installation
echo ""
echo "Installing packages"
echo "Package list: "
echo $packages
sudo $mngr install $packages
if test "$_flag_type" = gui
    echo ""
    rm -rf ./hawk
    mkdir ~/.local/bin/ 2>/dev/null
    git clone https://github.com/kratss/hawk
    mv ./hawk/hawk.fish ~/.local/bin/
    mv ./hawk/hawk-preview.fish ~/.local/bin/
    rm -rf ./hawk
end

echo ""
echo "Installing dot files"
git clone https://github.com/kratss/dotfiles.git >/dev/null
mkdir ~/.config 2>/dev/null
mkdir ~/.local/bin 2>/dev/null
cp -r ./dotfiles/* ~/.config/
#cp -r ./dotfiles/.local/bin/* ~/.local/bin/
rm -r -f ./dotfiles
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
if contains all $_flag_type
    echo "Enabling matrix-updater.service"
    systemctl --user enable matrix-updater.serivce
    systemctl --user status matrix-updater.service | head -n 3
end
##
### firefox
if contains gui $_flag_type
    firefox https://addons.mozilla.org/en-US/firefox/addon/tridactyl-vim/
    firefox https://addons.mozilla.org/en-US/firefox/addon/i-dont-care-about-cookies/
end


### lazyvim
# nvim.appimage because apt distros have ancient version of nvim
if type apt 2>/dev/null; and not test -e ~/.local/bin/nvim.appimage
    wget https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
    chmod +x nvim.appimage
    mkdir ~/.local/bin/
    mv nvim.appimage ~/.local/bin/
end

# get nerdfonts for pretty glyphs
if type apt 2>/dev/null
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/0xProto.zip
    unzip *.zip -d /usr/share/fonts
end
