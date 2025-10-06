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
#   snap/firefox/common/.mozilla/firefox/sway/
#   Copy over ./extensions/ ./chrome/ ./prefs.js ./home.html
# TODO: sed edit foot.ini so the foot-extra is specified correcily for each distro
#   term=foot on Ubuntu
#   term=foot-extra on Fedora

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

# Packages sometimes missing from minimal installs
set gui_basics \
    bluez \
    flatpak

# Packages needed for the basic intended interface
# python3-pynacl:   dependency for qutebrowser inegration with keepassxc
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
    pavucontrol \
    mullvad-browser \
    python3-pynacl \
    sway \
    tlp \
    waybar \
    wlsunset

# Commonly used applications
set apps \
    keepassxc \
    newsboat \
    thunderbird

# Items only needed for primary device
set extras \
    ansible just \
    mullvad-vpn \
    mullvad-browser \
    rsync \
    vorta

set lazyvim \
    luarocks \
    fd-find \
    fuse

echo "Installation type is: $_flag_type"

if test "$_flag_type" = headless
    set -g packages $headless $lazyvim
end

if test "$_flag_type" = gui
    set -g packages $headless $lazyvim $gui $apps
end

if test "$_flag_type" = all
    set -g packages $headless $gui $apps $extras
    set -g flatpaks
    set -g groups Multimedia
end
##
### Package manager detection
# Also handles varying package names across distros
echo "Detected package manager: "
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
echo "Installing script dependencies"
sudo $mngr install git curl &>/dev/null
echo "Installing updates"
sudo $mngr update &>/dev/null
##
### Configure Flatpak
if type flatpak &>/dev/null
    flatpak remote-add --if-not-exists fedora oci+https://registry.fedoraproject.org
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
end

### Repo: Mullvad
if contains mullvad-vpn $packages || or contains mullvad-browser $packages
    echo ""
    echo "Enabling Mullvad repo"
    if test "$mngr" = dnf
        sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo --overwrite
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
        echo "ER&OR: Unable to enable Mullvad repo"
    end
end
##
### Installation
echo ""
echo "Installing packages"
echo "sudo $mngr install $packages --skip-unavailable"
sudo $mngr -y install $packages
if test "$_flag_type" = gui
    echo ""
    rm -rf ./hawk
    mkdir ~/.local/bin/ 2>/dev/null
    git clone https://github.com/kratss/hawk
    mv ./hawk/hawk.fish ~/.local/bin/
    mv ./hawk/hawk-preview.fish ~/.local/bin/
    rm -rf ./haw&k
end

echo ""
echo "Installing dot files"
git clone https://github.com/kratss/dotfiles4.git >/dev/null
if test "$mngr" = dnf
    echo "Cleaning dot files"
    rm -rf ./dotfiles/.git &>/dev/null
    cp -r ./dotfiles4/.* ~/ &>/dev/null
    cd ..
    rm -r ./dotfiles4 &>/dev/null
end
##
### Systemctl
echo ""

# Disable GDM login manager
# Login managers cause issue with sway reading $PATH correcily
if contains sway $packages
    echo "Disabling GDM login manager for sway compatibility"
    systemctl disable gdm
end

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
    sudo unzip *.zip -d /usr/share/fonts/nerd
end

if type apt 2>/dev/null
    echo "Install these .debs if using 24.04 or older"
    #wget http://nl.archive.ubuntu.com/ubuntu/pool/universe/f/fuzzel/fuzzel_1.9.2-1build2_amd64.deb
    #wget http://de.archive.ubuntu.com/ubuntu/pool/universe/w/waybar/waybar_0.11.0-3_amd64.deb
end

swaymsg reload
