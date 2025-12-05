#!/usr/bin/env fish
# vim:foldmethod=marker:foldmarker=###,##

argparse apps extras 'type=?' -- $argv
or return 1
if test (count $argv) -eq 0 or contains -- --help $argv
    echo "No arguments provided"
    echo "Installation types:
--type=: Specify the desired installation type
  headless: config for headless installs
  gui: setup graphical environment
  all: everything needed for my main personal computer setup"
    exit
end

### Packages
# Basics are commonly installed utilities that may be missing on minimal installs
# Separated to reduce clutter
set headless_basics \
    encfs \
    plocate

set headless \
    $headless_basics \
    curl \
    dash \
    fish \
    fuzzel \
    fzf \
    git \
    gitui \
    gocryptfs \
    htop \
    NetworkManager-tui \
    neovim \
    nnn \
    trash-cli \
    tree \
    w3m \
    wl-clipboard

# Packages sometimes missing from minimal installs
set gui_basics bluez flatpak

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
    mako \
    mpv \
    pavucontrol \
    python3-nacl \
    qutebrowser \
    sway \
    tlp \
    waybar \
    wlsunset

# Commonly used applications
set apps gnome-software keepassxc newsboat thunderbird mullvad-browser

# Items only needed for primary device
# ansible: required for controlling matrix server 
# just: required for controlling matrix server
set extras ansible just mullvad-vpn mullvad-browser rsync vorta

set lazyvim \
    luarocks \
    fd-find \
    fuse

echo "Installation type is: $_flag_type"

if test "$_flag_type" = headless
    set -g packages $headless $lazyvim
else if test "$_flag_type" = gui
    set -g packages $headless $lazyvim $gui $apps
else if test "$_flag_type" = all
    set -g packages $headless $lazyvim $gui $apps $extras
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
sudo $mngr install git curl
echo "Installing updates"
sudo $mngr update
##
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
        echo "ERROR: Unable to enable Mullvad repo"
    end
end
##
### Installation
echo ""
echo "Installing packages"
echo "sudo $mngr install $packages --skip-unavailable"
sudo $mngr -y install $packages --skip-unavailable
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
echo "Cleaning dot files"
rm -rf ./dotfiles/.git &>/dev/null
cp -r ./dotfiles4/.* ~/ &>/dev/null
cd ..
rm -r ./dotfiles4 &>/dev/null

if type flatpak &>/dev/null
    echo ""
    echo "Installing flatpaks and flatpak repos"
    flatpak remote-add --if-not-exists fedora oci+https://registry.fedoraproject.org
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y fedora com.github.johnfactotum.Foliate
    flatpak install -y fedora org.gnome.Loupe
    flatpak install -y fedora org.gnome.Evince
    flatpak install -y im.riot.Riot
    flatpak install -y org.gnome.Podcasts
end
##
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

# Get nerdfonts for pretty glyphs
if type apt 2>/dev/null
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/0xProto.zip
    sudo unzip *.zip -d /usr/share/fonts/nerd
end
##
swaymsg reload
