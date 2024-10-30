#!/bin/bash
set -o errexit -o pipefail -o noclobber -o nounset

if [[ -n $SUDO_USER ]]; then
    echo "Warning: Assuming $SUDO_USER identity for the kiosk authority."
    echo "If this is wrong, stop execution and run the script as target user."
    USER=$SUDO_USER
fi

GIT_REPO_UPSTREAM=""
USER_FULLNAME="Kiosk User"

getopt --test > /dev/null && true
if [ $? -ne 4 ]; then
    echo "Command run with an incompatible getopt or backwards compatibility mode, exiting."
    exit 1
fi

LONGOPTS=skip-git-pull
OPTIONS=s
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")

eval set -- "$PARSED"

SKIP_GIT_PULL=false
while true; do
    case "$1" in
        -s|--skip-git-pull)
            SKIP_GIT_PULL=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: Unrecognized option $1"
            exit 3
            ;;
    esac
done

# Run system wide update to keep kiosk up to date
apt-get update -y && apt-get upgrade -y

# Skip pulling files from git repo if flag is present
# TODO: Pull release tarball from github instead of a whole repo
if [[ SKIP_GIT_PULL == false ]]; then
    apt-get install -y git

    # Check if install script is run from git repo, or standalone
    if [[ -d ./.git ]]; then
        git pull
    else
        GIT_REPO_TARGET=$(mktemp -d)
        git clone $GIT_REPO_UPSTREAM $GIT_REPO_TARGET
        cd $GIT_REPO_TARGET
    fi 
fi

# Install dependencies
apt-get install -y \
    xinput \
    i3 \
    unclutter \
    chromium \
    kitty \
    gdm3 \
    policykit-1-gnome

# Create kiosk user
useradd -m -s "/bin/bash" kiosk -c "$USER_FULLNAME" -G users && true
if [ $? -eq 9 ]; then
    # Check if exit(9) is caused by existing user or group
    # Condition is true if user exists
    if getent passwd kiosk > /dev/null 2>&1; then
        read -p "User kiosk already exists. Initialize in existing user? [y/n]." existing_user
        if [[ $existing_user != "y" ]]; then
            echo "Exiting installation. Please rename existing user and run the script again."
            exit 1
        fi
    else
        # Retry user creation, assuming the group is already present
        useradd -m -s "/bin/bash" kiosk -g kiosk -c "$USER_FULLNAME" -G users && true
    fi
elif [ $? -ne 0 ]; then
    echo "Error creating user kiosk. Exiting installation."
    exit 1
fi

echo "Changing password for kiosk user:"
passwd kiosk

echo "Skript was initialized as $USER."
echo "Adding $USER to kiosk group."
usermod -aG kiosk $USER

# Ask for autologin
read -p "Enable autologin for kiosk user? [y/n]" autologin
if [[ $autologin == "y" ]]; then
    sed -i 's/#  AutomaticLoginEnable = true/AutomaticLoginEnable = true/g' /etc/gdm3/daemon.conf
    sed -i 's/#  AutomaticLogin = user1/AutomaticLogin = kiosk/g' /etc/gdm3/daemon.conf
fi

# Copy remaining configs 
echo "Copying remaining configs to /home/kiosk/.kiosk."
chown -R kiosk:kiosk /home/kiosk
mkdir -p /home/kiosk/.kiosk # && cp -r
chown -R $USER:kiosk /home/kiosk/.kiosk
chmod -R 745 /home/kiosk/.kiosk

# Enable web filtering policies in chromium
echo "[0] None"
echo "[1] Blacklist"
echo "[2] Whitelist"
echo "[3] Custom"
read -p "What web traffic filtering policies to enable? [0-3]" web_filtering_policy

blacklist_urls[0]="*"
case $web_filtering_policy in
    0)
        echo "No web filtering policies enabled."
        ;;
    1)
        echo "Type URLs to blacklist, separated by spaces:"
        read -a blacklist_urls
        ;;
    2)
        echo "Type URLs to whitelist, separated by spaces:"
        read -a whitelist_urls
        ;;
    3)
        echo "
        Currently broken, please paste your custom policy directly to /etc/chromium/policies/managed/
        "
        ;;
    *)
        echo "Invalid option, no web filtering policies enabled."
        ;;
esac

POLICY_FILE="web_filtering_policy.json"
POLICY_SOURCE="/home/kiosk/.kiosk"
POLICY_TARGET="/etc/chromium/policies/managed"

if [ -f "$POLICY_SOURCE/$POLICY_FILE" ]; then
    read -p "File $POLICY_SOURCE/$POLICY_FILE already exists. Overwrite? [y/n]" overwrite
    if [[ $overwrite != "y" ]]; then
        echo "Exiting installation. Please rename existing file and run the script again."
        exit 1
    fi
fi
if [ -L "$POLICY_TARGET/$POLICY_FILE" ]; then
    read -p "File $POLICY_TARGET/$POLICY_FILE already exists. Overwrite? [y/n]" overwrite
    if [[ $overwrite != "y" ]]; then
        echo "Exiting installation. Please rename existing file and run the script again."
        exit 1
    else 
        rm "$POLICY_TARGET/$POLICY_FILE"
    fi
fi

# Generate web filtering policy file
# NOTE: Maybe add predefined exceptions, like chrome://, etc. 
echo "{
    \"URLBlockList\": [
        \"$(IFS=\",\ \"; echo "${blacklist_urls[*]}")\"
    ],
    \"URLAllowList\": [
        \"$(IFS=\",\ \"; echo "${whitelist_urls[*]}")\"
    ]
}" >| "$POLICY_SOURCE/$POLICY_FILE"

echo "Changing ownership over policy file"
chown $USER:kiosk "$POLICY_SOURCE/$POLICY_FILE"

# Create symlink to web filtering policy
mkdir -p /etc/chromium/policies/managed
# DEPRECATED: Has to be regular file
# ln -s "$POLICY_SOURCE/$POLICY_FILE" "$POLICY_TARGET/$POLICY_FILE
# NOTE: Maybe copy file on each boot of i3wm, instead of once during installation?
cp "$POLICY_SOURCE/$POLICY_FILE" "$POLICY_TARGET/$POLICY_FILE"

# Copy custom i3 config for user
# Assumes CWD is the root of the git repo
mkdir -p /home/kiosk/.config/i3 && chown -R kiosk:kiosk /home/kiosk 


# FIX: For some god forsaken reason, the touchscreen name has a \^M in the middle, idk how to automate over it
# 
# echo "Select your touchscreen device:"
# xinput list
# read -p "Enter touchscreen device name (or empty to skip touchscreen configuration): " touchscreen_device
#
# if [[ -n $touchscreen_device ]]; then
#     echo "[0] Portrait Left"
#     echo "[1] Portrait Right"
#     echo "[2] Landscape"
#     echo "[3] Landscape (flipped)"
#     read -p "Select screen orientation: [0-3]" screen_orientation
#     
#     sed -i 's/<touchscreen-name>/$touchscreen_device/g' ./i3/set-rotation.sh
#     sed -i 's/# exec --no-startup-id ~/.config/i3/set-rotation.sh/exec --no-startup-id ~/.config/i3/set-rotation.sh $screen_orientation/g' ./i3/config
# fi

cp -r ./i3 /home/kiosk/.config
chown -R $USER:kiosk /home/kiosk/.config/i3
chmod -R 755' /home/kiosk/.config/i3

read -p "Installation complete. Proceed with rebooting the system? [y/n]" reboot_bool
case $reboot_bool in
    y)
        reboot
        ;;
    *)
        echo "Installation complete. Please reboot the system to apply changes."
        ;;
esac
