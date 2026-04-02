#!/usr/bin/env fish
# vim:foldmethod=marker:foldmarker=###,##

### Read install type, packages, and distro
if test (count $argv) -eq 0
    echo "No arguments provided"
    echo "--type: Specify the desired installation type
  headless: config for headless installs
  gui: setup graphical environment
  apps: graphical environment + commoly used apps
  all: everything needed for my main personal computer setup"
    exit
end

argparse apps extras 'type=?' -- $argv
or return 1
echo "Installation type is: $_flag_type"

set distro (grep '^ID=' /etc/os-release | cut -d'=' -f2)
echo "Detected distro: $distro"
switch $distro
    case fedora
        set -g mngr dnf
    case debian ubuntu
        set -g mngr apt-get
    case opensuse-tumbleweed opensuse-leap
        set -g mngr zypper
        set -g group "install -t pattern"
    case "*"
        echo "Failed to detect distro"
        exit
end
echo "Installing script dependencies"
sudo $mngr install git curl yq
echo "Installing updates"
sudo $mngr update

# Read packages from YAML
cd (dirname (status --current-filename))
set headless (yq '.headless[]' packages.yaml)
set gui (yq '.gui[]' packages.yaml)
set apps (yq '.apps[]' packages.yaml)
set flatpaks (yq '.flatpaks[]' packages.yaml)
set primary_device (yq '.primary_device[]' packages.yaml)

switch $_flag_type
    case headless
        set -g packages $headless
        set -g install_flatpaks false
    case gui
        set -g packages $headless $gui
        set -g install_flatpaks false
    case apps
        set -g packages $headless $gui $apps
        set -g install_flatpaks true
    case all
        set -g packages $headless $gui $apps $primary_device
        set -g install_flatpaks true
        set -g groups Multimedia
end

# Handles varying package names across distros and other quirks
switch $distro
    case debian ubuntu
        set packages (string replace NetworkManager-tui "" $packages)
        set packages (string replace gitui "git-gui" $packages)
    case opensuse-tumbleweed opensuse-leap
        set packages (string replace nmtui NetworkManager-tui $packages)
        set packages (string replace foot-extra foot-extra-terminfo $packages)
end
##
### Add Mullvad repo
if contains mullvad-vpn $packages || or contains mullvad-browser $packages
    echo ""
    echo "Enabling Mullvad repo"
    switch $distro
        case fedora
            sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo --overwrite
        case debian ubuntu
            sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc \
                https://repository.mullvad.net/deb/mullvad-keyring.asc
            echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc \
  arch=$( dpkg --print-architecture )] \
  https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" \
                | sudo tee /etc/apt/sources.list.d/mullvad.list
            sudo apt-get update
        case opensuse-tumbleweed opensuse-leap
            sudo zypper addrepo -f https://repository.mullvad.net/rpm/stable/mullvad.repo
        case '*'
            echo "ERROR: Unable to enable Mullvad repo"
            exit
    end
end
##
### Install packages and dotfiles
echo ""
echo "Installing dot files"
git clone --depth 1 https://github.com/kratss/dotfiles.git >/dev/null
rm -rf ./dotfiles/.git &>/dev/null
cp -r ./dotfiles/.* ~/ &>/dev/null
rm -r ./dotfiles &>/dev/null

echo ""
echo "Installing packages"
echo "sudo $mngr install $packages --skip-unavailable"
sudo $mngr -y install $packages --skip-unavailable
if $install_flatpaks
    for flatpak_package in $flatpaks
        eval $flatpak_package
    end
end
if contains -- "$_flag_type" gui all
    curl -o ~/.local/bin/hawk.fish https://raw.githubusercontent.com/kratss/hawk/refs/heads/master/hawk.fish
    curl -o ~/.local/bin/hawk-preview.fish https://raw.githubusercontent.com/kratss/hawk/refs/heads/master/hawk-preview.fish
end

##
### Enable Systemd services
echo ""
systemctl enable --user ~/.config/systemd/user/*.service # Enable all services in config folder
systemctl enable --user ~/.config/systemd/user/*.timer
systemctl enable --user ~/.config/systemd/user/*.socket
contains sway $packages; and systemctl disable gdm # GDM causes sway to read $PATH incorrectly
contains bluez $pacages; and systemctl enable bluetooth
##
### lazyvim
# Get nerdfonts for pretty glyphs
#if type apt 2>/dev/null
#    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/0xProto.zip
#    sudo unzip *.zip -d /usr/share/fonts/nerd
#    rm -r 0xProto
#end
##
swaymsg reload
