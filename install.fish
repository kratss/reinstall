#!/usr/bin/env fish
# vim:foldmethod=marker:foldmarker=###,##

### Read install type, packages, and distro
if test (count $argv) -eq 0 #or contains -- --help $argv
    echo "No arguments provided"
    echo "Installation types:
--type=: Specify the desired installation type
  headless: config for headless installs
  gui: setup graphical environment
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
set headless (yq '.headless[]' packages.yaml)
set gui (yq '.gui[]' packages.yaml)
set primary_device (yq '.primary_device[]' packages.yaml)
set apps (yq '.apps[]' packages.yaml)
set flatpaks (yq '.flatpaks[]' packages.yaml)

switch $_flag_type
    case headless
        set -g packages $headless
    case gui
        set -g packages $headless $gui
    case all
        set -g packages $headless $gui $apps $primary_device
        set -g flatpaks
        set -g groups Multimedia
end
# Handles varying package names across distros and other quirks
switch $distro
    case debian ubuntu
        set packages (string replace NetworkManager-tui "" $packages)
        set packages (string replace gitui "git-gui" $packages)
    case opensuse-tumbleweed opensuse-leap
        set packages (string replace nmtui      NetworkManager-tui $packages)
        set packages (string replace foot-extra foot-extra-terminfo $packages)
end
##
### Repo: Mullvad
if contains mullvad-vpn $packages || or contains mullvad-browser $packages
    echo ""
    echo "Enabling Mullvad repo"
    switch $distro
        case dnf
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
    end
end
##
### Installation
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
if type flatpak &>/dev/null
    for flatpak_package in $flatpaks
        $flatpak_package
    end
end
if test "$_flag_type" = gui
    curl -o ~/.local/bin/hawk.fish https://raw.githubusercontent.com/kratss/hawk/refs/heads/master/hawk.fish
    curl -o ~/.local/bin/hawk-preview.fish https://raw.githubusercontent.com/kratss/hawk/refs/heads/master/hawk-preview.fish
end

##
### Systemctl
echo ""

# Helper function to enable the service name passed to it
function enable_service -a service -a user_flag
    echo "Enabling $service.service"
    systemctl $user_flag enable $service.service
    systemctl $user_flag start $service.service
    systemctl $user_flag status $service.service | head -n 3
end
# Disable GDM login manager
# Login managers cause issue with sway reading $PATH correcily
if contains sway $packages
    echo "Disabling GDM login manager for sway compatibility"
    systemctl disable gdm
end

# Syncthing
if contains syncthing $packages
    enable_service syncthing --user
end

# Bluetooth
if contains bluez $packages
    enable_service bluez
end

# Matrix server updater
if contains all $_flag_type
    enable_service matrix-updater --user
end
##
### lazyvim
# Get nerdfonts for pretty glyphs
if type apt 2>/dev/null
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/0xProto.zip
    sudo unzip *.zip -d /usr/share/fonts/nerd
    rm -r 0xProto
end
##
swaymsg reload
