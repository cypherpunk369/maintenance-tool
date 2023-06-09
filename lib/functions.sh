#! /bin/bash

#variables
BRANCH='stable'
DEVICE='rpi4'
EDITION='minimal'
VERSION=$(date +'%y'.'%m')
LIBDIR=/usr/share/manjaro-arm-tools/lib
BUILDDIR=/var/lib/manjaro-arm-tools/pkg
BUILDSERVER=https://repo.manjaro.org/repo
PACKAGER=$(cat /etc/makepkg.conf | grep PACKAGER)
PKGDIR=/var/cache/manjaro-arm-tools/pkg
ROOTFS_IMG=/var/lib/manjaro-arm-tools/img
TMPDIR=/var/lib/manjaro-arm-tools/tmp
IMGDIR=/var/cache/manjaro-arm-tools/img
IMGNAME=Manjaro-ARM-$EDITION-$DEVICE-$VERSION
PROFILES=/usr/share/manjaro-arm-tools/profiles
NSPAWN='systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D'
OSDN='storage.osdn.net:/storage/groups/m/ma/manjaro-arm'
STORAGE_USER=$(whoami)
FLASHVERSION=$(date +'%y'.'%m')
ARCH='aarch64'
USER='manjaro'
HOSTNAME='manjaro-arm'
PASSWORD='manjaro'
CARCH=$(uname -m)
COLORS=true
FILESYSTEM='ext4'
srv_list=/tmp/services_list

PROGNAME=${0##*/}

#import conf file
source /etc/manjaro-arm-tools/manjaro-arm-tools.conf 

# PKGDIR & IMGDIR may not exist if they were changed by configuration, make sure they do.
mkdir -p ${PKGDIR}/pkg-cache
mkdir -p ${IMGDIR}

usage_deploy_img() {
    echo "Usage: ${0##*/} [options]"
    echo "    -i <image>         Image to upload. Should be a .xz file."
    echo "    -d <device>        Device the image is for. [Default = rpi4. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/devices/")]"
    echo "    -e <edition>       Edition of the image. [Default = minimal. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/editions/")]"
    echo "    -v <version>       Version of the image. [Default = Current YY.MM]"
    echo "    -k <gpg key ID>    Email address associated with the GPG key to use for signing"
    echo "    -u <username>      Username of your OSDN user account with access to upload [Default = currently logged in local user]"
    echo "    -t                 Create a torrent of the image"
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

usage_build_pkg() {
    echo "Usage: ${0##*/} [options]"
    echo "    -a <arch>          Architecture. [Default = aarch64. Options = any or aarch64]"
    echo "    -p <pkg>           Package to build"
    echo "    -k                 Keep the previous rootfs for this build"
    echo "    -b <branch>        Set the branch used for the build. [Default = stable. Options = stable, testing or unstable]"
    echo "    -n                 Install built package into rootfs"
    echo "    -i <package>       Install local package into rootfs."
    echo "    -r <repository>    Use a custom repository in the rootfs."
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

usage_build_img() {
    echo "Usage: ${0##*/} [options]"
    echo "    -d <device>        Device the image is for. [Default = rpi4. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/devices/")]"
    echo "    -e <edition>       Edition of the image. [Default = minimal. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/editions/")]"
    echo "    -v <version>       Define the version the resulting image should be named. [Default is current YY.MM]"
    echo "    -k <repo>          Add overlay repo [Options = kde-unstable, mobile] or url https://server/path/custom_repo.db"
    echo "    -i <package>       Install local package into image rootfs."
    echo "    -b <branch>        Set the branch used in the image. [Default = stable. Options = stable, testing or unstable]"
    echo "    -m                 Create bmap. ('bmap-tools' need to be installed.)"
    echo "    -n                 Force download of new rootfs."
    echo "    -s <hostname>      Use custom hostname"
    echo "    -x                 Don't compress the image."
    echo "    -c                 Disable colors."
    echo "    -f                 Create an image with factory settings."
    echo "    -p <filesystem>    Filesystem to be used for the root partition. [Default = ext4. Options = ext4 or btrfs]"
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

usage_build_emmcflasher() {
    echo "Usage: ${0##*/} [options]"
    echo "    -d <device>        Device the image is for. [Default = rpi4. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/devices/")]"
    echo "    -e <edition>       Edition of the image to download. [Default = minimal. Options = $(ls -m --width=0 "$PROFILES/arm-profiles/editions/")]"
    echo "    -v <version>       Define the version of the release to download. [Default is current YY.MM]"
    echo "    -f <flash version> Version of the eMMC flasher image it self. [Default is current YY.MM]"
    echo "    -i <package>       Install local package into image rootfs."
    echo "    -n                 Force download of new rootfs."
    echo "    -x                 Don't compress the image."
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

usage_getarmprofiles() {
    echo "Usage: ${0##*/} [options]"
    echo '    -f                 Force download of current profiles from the git repository'
    echo '    -p                 Use profiles from pp-factory branch'
    echo '    -h                 This help'
    echo ''
    echo ''
    exit $1
}

enable_colors() {
    ALL_OFF="\e[1;0m"
    BOLD="\e[1;1m"
    GREEN="${BOLD}\e[1;32m"
    BLUE="${BOLD}\e[1;34m"
}

msg() {
    local mesg=$1; shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
 }
 
info() {
    local mesg=$1; shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
 }

error() {
    local mesg=$1; shift
    printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

cleanup() {
    umount $ROOTFS_IMG/rootfs_$ARCH/var/cache/pacman/pkg
    exit ${1:-0}
}

abort() {
    error 'Aborting...'
    cleanup 255
}

prune_cache(){
    info "Prune and unmount pkg-cache..."
    $NSPAWN $CHROOTDIR paccache -r
    umount $PKG_CACHE
}

load_vars() {
    local var

    [[ -f $1 ]] || return 1

    for var in {SRC,SRCPKG,PKG,LOG}DEST MAKEFLAGS PACKAGER CARCH GPGKEY; do
        [[ -z ${!var} ]] && eval $(grep -a "^${var}=" "$1")
    done

    return 0
}

get_timer(){
    echo $(date +%s)
}

# $1: start timer
elapsed_time(){
    echo $(echo $1 $(get_timer) | awk '{ printf "%0.2f",($2-$1)/60 }')
}

show_elapsed_time(){
    msg "Time %s: %s minutes..." "$1" "$(elapsed_time $2)"
}

create_torrent() {
    info "Creating torrent of $IMAGE..."
    cd $IMGDIR/
    mktorrent -v -a udp://tracker.opentrackr.org:1337 -w https://osdn.net/dl/manjaro-arm/$IMAGE -o $IMAGE.torrent $IMAGE
}

checkroot () {
    if [ "$EUID" -ne 0 ]
    then echo "This script requires root permissions to run. Please run as root or with sudo!"
	 exit
    fi
}

checkbranch () {
    if [[ "$BRANCH" != "stable" && "$BRANCH" != "testing" && "$BRANCH" != "unstable" ]]; then
	msg "Unknown branch. Please use either, stable, testing or unstable!"
	exit 1
    fi
}

checkrunning() {
    for pid in $(pidof -x $PROGNAME); do
    if [ $pid != $$ ]; then
        echo "[$(date)] : $PROGNAME : Process is already running with PID $pid"
        exit 1
    fi
    done
}

checksum_img() {
    # Create checksums for the image
    info "Creating checksums for [$IMAGE]..."
    cd $IMGDIR/
    sha1sum $IMAGE > $IMAGE.sha1
    sha256sum $IMAGE > $IMAGE.sha256
    info "Creating signature for [$IMAGE]..."
    gpg --detach-sign -u $GPGMAIL "$IMAGE"
    if [ ! -f "$IMAGE.sig" ]; then
        echo "Image not signed. Aborting..."
        exit 1
    fi
}

img_upload() {
    # Upload image + checksums to image server
    msg "Uploading image and checksums to server..."
    info "Please use your server login details..."
    img_name=${IMAGE%%.*}
    rsync -raP $img_name* $STORAGE_USER@$OSDN/$DEVICE/$EDITION/$VERSION/
}

create_rootfs_pkg() {
    msg "Building $PACKAGE for $ARCH..."
    # Remove old rootfs if it exists
    if [ -d $CHROOTDIR ]; then
        info "Removing old rootfs..."
        rm -rf $CHROOTDIR
    fi
    msg "Creating rootfs..."
    # cd to rootfs
    mkdir -p $CHROOTDIR
    # basescrap the rootfs filesystem
    info "Switching branch to $BRANCH..."
    sed -i s/"arm-stable"/"arm-$BRANCH"/g $LIBDIR/pacman.conf.$ARCH
    $LIBDIR/pacstrap -G -M -C $LIBDIR/pacman.conf.$ARCH $CHROOTDIR fakeroot-qemu base-devel
    echo "Server = $BUILDSERVER/arm-$BRANCH/\$repo/\$arch" > $CHROOTDIR/etc/pacman.d/mirrorlist
    sed -i s/"arm-$BRANCH"/"arm-stable"/g $LIBDIR/pacman.conf.$ARCH
    if [[ $CARCH != "aarch64" ]]; then
        # Enable cross architecture Chrooting
        cp /usr/bin/qemu-aarch64-static $CHROOTDIR/usr/bin/
    fi

    msg "Configuring rootfs for building..."
    $NSPAWN $CHROOTDIR pacman-key --init 1> /dev/null 2>&1
    $NSPAWN $CHROOTDIR pacman-key --populate archlinuxarm manjaro manjaro-arm 1> /dev/null 2>&1
    cp $LIBDIR/makepkg $CHROOTDIR/usr/bin/
    $NSPAWN $CHROOTDIR chmod +x /usr/bin/makepkg 1> /dev/null 2>&1
    $NSPAWN $CHROOTDIR update-ca-trust
    if [[ ! -z ${CUSTOM_REPO} ]]; then
        info "Adding repo [$CUSTOM_REPO] to rootfs"

        if [[ "$CUSTOM_REPO" =~ ^https?://.*db ]]; then
            CUSTOM_REPO_NAME="${CUSTOM_REPO##*/}" # remove everyting before last slash
            CUSTOM_REPO_NAME="${CUSTOM_REPO_NAME%.*}" # remove everything after last dot
            CUSTOM_REPO_URL="${CUSTOM_REPO%/*}" # remove everything after last slash
            sed -i "s/^\[core\]/\[$CUSTOM_REPO_NAME\]\nSigLevel = Optional TrustAll\nServer = ${CUSTOM_REPO_URL//\//\\/}\n\n\[core\]/" $CHROOTDIR/etc/pacman.conf
        else
            sed -i "s/^\[core\]/\[$CUSTOM_REPO\]\nInclude = \/etc\/pacman.d\/mirrorlist\n\n\[core\]/" $CHROOTDIR/etc/pacman.conf
        fi
    fi
    sed -i s/'#PACKAGER="John Doe <john@doe.com>"'/"$PACKAGER"/ $CHROOTDIR/etc/makepkg.conf
    sed -i s/'#MAKEFLAGS="-j2"'/'MAKEFLAGS="-j$(nproc)"'/ $CHROOTDIR/etc/makepkg.conf
    sed -i s/'COMPRESSXZ=(xz -c -z -)'/'COMPRESSXZ=(xz -c -z - --threads=0)'/ $CHROOTDIR/etc/makepkg.conf
    $NSPAWN $CHROOTDIR pacman -Syy
}

create_rootfs_img() {
    #Check if device file exists
    if [ ! -f "$PROFILES/arm-profiles/devices/$DEVICE" ]; then 
        echo 'Invalid device '$DEVICE', please choose one of the following'
        echo "$(ls $PROFILES/arm-profiles/devices/)"
        exit 1
    fi
    #check if edition file exists
    if [ ! -f "$PROFILES/arm-profiles/editions/$EDITION" ]; then 
        echo 'Invalid edition '$EDITION', please choose one of the following'
        echo "$(ls $PROFILES/arm-profiles/editions/)"
        exit 1
    fi
    msg "Creating image of $EDITION for $DEVICE..."
    # Remove old rootfs if it exists
    if [ -d $ROOTFS_IMG/rootfs_$ARCH ]; then
        info "Removing old rootfs..."
        rm -rf $ROOTFS_IMG/rootfs_$ARCH
    fi
    mkdir -p $ROOTFS_IMG/rootfs_$ARCH
    if [[ "$KEEPROOTFS" = "false" ]]; then
        rm -rf $ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz*
        # fetch and extract rootfs
        info "Downloading latest $ARCH rootfs..."
        cd $ROOTFS_IMG
        wget -q --show-progress --progress=bar:force:noscroll https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz
    fi
    #also fetch it, if it does not exist
    if [ ! -f "$ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz" ]; then
        cd $ROOTFS_IMG
        wget -q --show-progress --progress=bar:force:noscroll https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz
    fi
    
    info "Extracting $ARCH rootfs..."
    bsdtar -xpf $ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz -C $ROOTFS_IMG/rootfs_$ARCH
    
    info "Setting up keyrings..."
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman-key --init 1>/dev/null || abort
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman-key --populate archlinuxarm manjaro manjaro-arm 1>/dev/null || abort
    
    if [[ ! -z ${CUSTOM_REPO} ]]; then
        info "Adding repo [$CUSTOM_REPO] to rootfs"

        if [[ "$CUSTOM_REPO" =~ ^https?://.*db ]]; then
            CUSTOM_REPO_NAME="${CUSTOM_REPO##*/}" # remove everyting before last slash
            CUSTOM_REPO_NAME="${CUSTOM_REPO_NAME%.*}" # remove everything after last dot
            CUSTOM_REPO_URL="${CUSTOM_REPO%/*}" # remove everything after last slash
            sed -i "s/^\[core\]/\[$CUSTOM_REPO_NAME\]\nSigLevel = Optional TrustAll\nServer = ${CUSTOM_REPO_URL//\//\\/}\n\n\[core\]/" $ROOTFS_IMG/rootfs_$ARCH/etc/pacman.conf
        else
            sed -i "s/^\[core\]/\[$CUSTOM_REPO\]\nInclude = \/etc\/pacman.d\/mirrorlist\n\n\[core\]/" $ROOTFS_IMG/rootfs_$ARCH/etc/pacman.conf
        fi
    fi

    info "Setting branch to $BRANCH..."
    echo "Server = $BUILDSERVER/arm-$BRANCH/\$repo/\$arch" > $ROOTFS_IMG/rootfs_$ARCH/etc/pacman.d/mirrorlist
    
    msg "Installing packages for $EDITION edition on $DEVICE..."
    # Install device and editions specific packages
    mount -o bind $PKGDIR/pkg-cache $PKG_CACHE
    case "$EDITION" in
        cubocore|phosh|plasma-mobile|plasma-mobile-dev|kde-bigscreen|maui-shell|nemomobile)
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -Syyu base systemd systemd-libs manjaro-system manjaro-release $PKG_EDITION $PKG_DEVICE --noconfirm || abort
            ;;
        minimal|server)
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -Syyu base systemd systemd-libs dialog manjaro-arm-oem-install manjaro-system manjaro-release $PKG_EDITION $PKG_DEVICE --noconfirm || abort
            ;;
        *)
            if [[ "$DEVICE" = "clockworkpi-a06" ]]; then # This device does not support Calamares, because of the low pixel height of the display (480)
                $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -Syyu base systemd systemd-libs dialog manjaro-arm-oem-install manjaro-system manjaro-release $PKG_EDITION $PKG_DEVICE --noconfirm || abort
            else
                $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -Syyu base systemd systemd-libs calamares-arm-oem manjaro-system manjaro-release $PKG_EDITION $PKG_DEVICE --noconfirm || abort
            fi
            ;;
    esac

    if [[ ! -z "$ADD_PACKAGE" ]]; then
        installLocalPackage
        # The list of packages is generated in installLocalPackage()
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -U $listForPacman --noconfirm || abort
        if [[ $? != 0 ]]; then
            echo -e "ERROR:\nThere was a problem with installing the local package/s.\nPlease,check the logs."
            exit 1 # TODO: Verify that the exit will be clean
        fi
    fi

    info "Generating mirrorlist..."
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman-mirrors --protocols https --method random --api --set-branch $BRANCH 1> /dev/null 2>&1
    
    info "Enabling services..."
    # Enable services
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl enable getty.target 1> /dev/null 2>&1
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl enable pacman-init.service 1> /dev/null 2>&1
    if [[ "$CUSTOM_REPO" = "kde-unstable" ]]; then
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl enable sshd.service 1> /dev/null 2>&1
    fi


    while read service; do
        if [ -e $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/$service ]; then
            echo "Enabling $service ..."
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl enable $service 1> /dev/null 2>&1
        else
            echo "$service not found in rootfs. Skipping."
        fi
    done < $srv_list

    info "Applying overlay for $EDITION edition..."
    cp -ap $PROFILES/arm-profiles/overlays/$EDITION/* $ROOTFS_IMG/rootfs_$ARCH/

    info "Setting up system settings..."
    #system setup
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH update-ca-trust
    echo "$HOSTNAME" | tee --append $ROOTFS_IMG/rootfs_$ARCH/etc/hostname 1> /dev/null 2>&1
    case "$EDITION" in
        cubocore|plasma-mobile|plasma-mobile-dev|kde-bigscreen|maui-shell)
            echo "No OEM setup!"
            # Lock root user
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH passwd --lock root
            ;;
        phosh|lomiri)
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH groupadd -r autologin
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH gpasswd -a "$USER" autologin
            # Lock root user
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH passwd --lock root
            ;;
        nemomobile)
            echo "Create user manjaro for nemomobile..."
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH groupadd -r autologin
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH useradd -m -g users -G wheel,sys,audio,input,video,storage,lp,network,users,power,autologin -p $(openssl passwd -6 123456) -s /bin/bash manjaro
            ;;
        minimal|server)
            echo "Enabling SSH login for root user for headless setup..."
            sed -i s/"#PermitRootLogin prohibit-password"/"PermitRootLogin yes"/g $ROOTFS_IMG/rootfs_$ARCH/etc/ssh/sshd_config
            sed -i s/"#PermitEmptyPasswords no"/"PermitEmptyPasswords yes"/g $ROOTFS_IMG/rootfs_$ARCH/etc/ssh/sshd_config
            echo "Enabling autologin for first setup..."
            mv $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service.bak
            cp $LIBDIR/getty\@.service $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service
            ;;
    esac
    if [[ "$DEVICE" = "clockworkpi-a06" ]]; then # device does not support Calamares because of low screen resolution, so enable TUI OEM setup on it
        echo "Enabling SSH login for root user for headless setup..."
        sed -i s/"#PermitRootLogin prohibit-password"/"PermitRootLogin yes"/g $ROOTFS_IMG/rootfs_$ARCH/etc/ssh/sshd_config
        sed -i s/"#PermitEmptyPasswords no"/"PermitEmptyPasswords yes"/g $ROOTFS_IMG/rootfs_$ARCH/etc/ssh/sshd_config
        echo "Enabling autologin for first setup..."
        mv $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service.bak
        cp $LIBDIR/getty\@.service $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/getty\@.service
        if [ -e $ROOTFS_IMG/rootfs_$ARCH/usr/bin/lightdm ]; then
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl disable lightdm.service 1> /dev/null 2>&1
        elif [ -e $ROOTFS_IMG/rootfs_$ARCH/usr/bin/sddm ]; then
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl disable sddm.service 1> /dev/null 2>&1
        elif [ -e $ROOTFS_IMG/rootfs_$ARCH/usr/bin/gdm ]; then
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl disable gdm.service 1> /dev/null 2>&1
        elif [ -e $ROOTFS_IMG/rootfs_$ARCH/usr/bin/greetd ]; then
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH systemctl disable greetd.service 1> /dev/null 2>&1
        fi
    fi
    
    # Create OEM user
    if [ -d $ROOTFS_IMG/rootfs_$ARCH/usr/share/calamares ]; then
        echo "Creating OEM user..."
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH groupadd -r autologin
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH useradd -m -g users -u 984 -G wheel,sys,audio,input,video,storage,lp,network,users,power,autologin -p $(openssl passwd -6 oem) -s /bin/bash oem
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH echo "oem ALL=(ALL) NOPASSWD: ALL" > $ROOTFS_IMG/rootfs_$ARCH/etc/sudoers.d/g_oem
        case "$EDITION" in
            desq|wayfire|sway)
                SESSION=$(ls $ROOTFS_IMG/rootfs_$ARCH/usr/share/wayland-sessions/ | head -1)
                ;;
            *)
                SESSION=$(ls $ROOTFS_IMG/rootfs_$ARCH/usr/share/xsessions/ | head -1)
                ;;
        esac
        # For sddm based systems
        if [ -f $ROOTFS_IMG/rootfs_$ARCH/usr/bin/sddm ]; then
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkdir -p /etc/sddm.conf.d
            echo "# Created by Manjaro ARM OEM Setup

[Autologin]
User=oem
Session=$SESSION" > $ROOTFS_IMG/rootfs_$ARCH/etc/sddm.conf.d/90-autologin.conf
        fi
        # For lightdm based systems
        if [ -f $ROOTFS_IMG/rootfs_$ARCH/usr/bin/lightdm ]; then
            SESSION=$(echo ${SESSION%.*})
            sed -i s/"#autologin-user="/"autologin-user=oem"/g $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm.conf
            sed -i s/"#autologin-user-timeout=0"/"autologin-user-timeout=0"/g $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm.conf
            if [[ "$EDITION" = "lxqt" ]]; then
                sed -i s/"#autologin-session="/"autologin-session=lxqt"/g $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm.conf
            elif [[ "$EDITION" = "i3" ]]; then
                echo "autologin-user=oem
autologin-user-timeout=0
autologin-session=i3" >> $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm.conf
                sed -i s/"# Autostart applications"/"# Autostart applications\nexec --no-startup-id sudo -E calamares"/g $ROOTFS_IMG/rootfs_$ARCH/home/oem/.i3/config
            else
                sed -i s/"#autologin-session="/"autologin-session=$SESSION"/g $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm.conf
            fi
        fi
        # For greetd based Sway edition
        if [ -f $ROOTFS_IMG/rootfs_$ARCH/usr/bin/sway ]; then
            echo '[initial_session]
command = "sway --config /etc/greetd/oem-setup"
user = "oem"' >> $ROOTFS_IMG/rootfs_$ARCH/etc/greetd/config.toml
        fi
        # For Gnome edition
        if [ -f $ROOTFS_IMG/rootfs_$ARCH/usr/bin/gdm ]; then
            sed -i s/"\[daemon\]"/"\[daemon\]\nAutomaticLogin=oem\nAutomaticLoginEnable=True"/g $ROOTFS_IMG/rootfs_$ARCH/etc/gdm/custom.conf
        fi
    fi
    
    # Lomiri services Temporary in function until it is moved to an individual package.
    if [[ "$EDITION" = "lomiri" ]]; then
        echo "Fix indicators"
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkdir -pv /usr/lib/systemd/user/ayatana-indicators.target.wants
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-datetime.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-datetime.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-display.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-display.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-messages.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-messages.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-power.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-power.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-session.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-session.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/ayatana-indicator-sound.service /usr/lib/systemd/user/ayatana-indicators.target.wants/ayatana-indicator-sound.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/indicator-network.service /usr/lib/systemd/user/ayatana-indicators.target.wants/indicator-network.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/indicator-transfer.service /usr/lib/systemd/user/ayatana-indicators.target.wants/indicator-transfer.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/indicator-bluetooth.service /usr/lib/systemd/user/ayatana-indicators.target.wants/indicator-bluetooth.service
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/indicator-location.service /usr/lib/systemd/user/ayatana-indicators.target.wants/indicator-location.service
        
        echo "Fix background"
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkdir -pv /usr/share/backgrounds
        #$NSPAWN $ROOTFS_IMG/rootfs_$ARCH convert -verbose /usr/share/wallpapers/manjaro.jpg /usr/share/wallpapers/manjaro.png
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/share/wallpapers/manjaro.png /usr/share/backgrounds/warty-final-ubuntu.png
        
        echo "Fix Maliit"
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkdir -pv /usr/lib/systemd/user/graphical-session.target.wants
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH ln -sfv /usr/lib/systemd/user/maliit-server.service /usr/lib/systemd/user/graphical-session.target.wants/maliit-server.service
    fi
    ### Lomiri Temporary service ends here 

    echo "Correcting permissions from overlay..."
    chown -R 0:0 $ROOTFS_IMG/rootfs_$ARCH/etc
    chown -R 0:0 $ROOTFS_IMG/rootfs_$ARCH/usr/{local,share}
    if [[ -d $ROOTFS_IMG/rootfs_$ARCH/etc/polkit-1/rules.d ]]; then
        chown 0:102 $ROOTFS_IMG/rootfs_$ARCH/etc/polkit-1/rules.d
    fi
    if [[ -d $ROOTFS_IMG/rootfs_$ARCH/usr/share/polkit-1/rules.d ]]; then
        chown 0:102 $ROOTFS_IMG/rootfs_$ARCH/usr/share/polkit-1/rules.d
    fi
    
    if [[ "$FILESYSTEM" = "btrfs" ]]; then
        info "Adding btrfs support to system..."
        if [ -f $ROOTFS_IMG/rootfs_$ARCH/boot/extlinux/extlinux.conf ]; then
            sed -i 's/APPEND/& rootflags=subvol=@/' $ROOTFS_IMG/rootfs_$ARCH/boot/extlinux/extlinux.conf
        elif [ -f $ROOTFS_IMG/rootfs_$ARCH/boot/boot.ini ]; then
            sed -i 's/setenv bootargs "/&rootflags=subvol=@ /' $ROOTFS_IMG/rootfs_$ARCH/boot/boot.ini
        elif [ -f $ROOTFS_IMG/rootfs_$ARCH/boot/uEnv.ini ]; then
            sed -i 's/setenv bootargs "/&rootflags=subvol=@ /' $ROOTFS_IMG/rootfs_$ARCH/boot/uEnv.ini
        #elif [ -f $ROOTFS_IMG/rootfs_$ARCH/boot/cmdline.txt ]; then
        #    sed -i 's/^/rootflags=subvol=@ rootfstype=btrfs /' $ROOTFS_IMG/rootfs_$ARCH/boot/cmdline.txt
        elif [ -f $ROOTFS_IMG/rootfs_$ARCH/boot/boot.txt ]; then
            sed -i 's/setenv bootargs/& rootflags=subvol=@/' $ROOTFS_IMG/rootfs_$ARCH/boot/boot.txt
            $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d /boot/boot.txt /boot/boot.scr
        fi
        echo "LABEL=ROOT_MNJRO / btrfs  subvol=@,compress=zstd,defaults,noatime  0  0" >> $ROOTFS_IMG/rootfs_$ARCH/etc/fstab
        echo "LABEL=ROOT_MNJRO /home btrfs  subvol=@home,compress=zstd,defaults,noatime  0  0" >> $ROOTFS_IMG/rootfs_$ARCH/etc/fstab
        sed -i '/^MODULES/{s/)/ btrfs)/}' $ROOTFS_IMG/rootfs_$ARCH/etc/mkinitcpio.conf
        $NSPAWN $ROOTFS_IMG/rootfs_$ARCH mkinitcpio -P 1> /dev/null 2>&1
    fi
    
	if [[ "$FACTORY" = "true" ]]; then
	info "Making settings for factory specific image..."
        case "$EDITION" in
            kde-plasma)
                sed -i s/"manjaro-arm.png"/"manjaro-pine64-2b.png"/g $ROOTFS_IMG/rootfs_$ARCH/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
                ;;
            xfce)
                sed -i s/"manjaro-arm.png"/"manjaro-pine64-2b.png"/g $ROOTFS_IMG/rootfs_$ARCH/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
                sed -i s/"manjaro-arm.png"/"manjaro-pine64-2b.png"/g $ROOTFS_IMG/rootfs_$ARCH/etc/lightdm/lightdm-gtk-greeter.conf
                ;;
        esac
        sed -i "s/arm-$BRANCH/arm-stable/g" $ROOTFS_IMG/rootfs_$ARCH/etc/pacman.d/mirrorlist
        sed -i "s/arm-$BRANCH/arm-stable/g" $ROOTFS_IMG/rootfs_$ARCH/etc/pacman-mirrors.conf
        echo "$EDITION - $(date +'%y'.'%m'.'%d')" | tee --append $ROOTFS_IMG/rootfs_$ARCH/etc/factory-version 1> /dev/null 2>&1
    else
        echo "$DEVICE - $EDITION - $VERSION" | tee --append $ROOTFS_IMG/rootfs_$ARCH/etc/manjaro-arm-version 1> /dev/null 2>&1
    fi
    
    msg "Creating package list: [$IMGDIR/$IMGNAME-pkgs.txt]"
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman -Qr / > $ROOTFS_IMG/rootfs_$ARCH/var/tmp/pkglist.txt 2>/dev/null
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH sed -i '1s/^[^l]*l//' /var/tmp/pkglist.txt
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH sed -i '$d' /var/tmp/pkglist.txt
    mv $ROOTFS_IMG/rootfs_$ARCH/var/tmp/pkglist.txt "$IMGDIR/$IMGNAME-pkgs.txt"
    
    info "Cleaning rootfs for unwanted files..."
    prune_cache
    rm $ROOTFS_IMG/rootfs_$ARCH/usr/bin/qemu-aarch64-static
    rm -f $ROOTFS_IMG/rootfs_$ARCH/var/log/* 1> /dev/null 2>&1
    rm -rf $ROOTFS_IMG/rootfs_$ARCH/var/log/journal/*
    rm -rf $ROOTFS_IMG/rootfs_$ARCH/etc/*.pacnew
    rm -rf $ROOTFS_IMG/rootfs_$ARCH/usr/lib/systemd/system/systemd-firstboot.service
    rm -rf $ROOTFS_IMG/rootfs_$ARCH/etc/machine-id
    rm -rf $ROOTFS_IMG/rootfs_$ARCH/etc/pacman.d/gnupg

    msg "$DEVICE $EDITION rootfs complete"
}

create_emmc_install() {
    msg "Creating eMMC install image of $EDITION for $DEVICE..."
    # Remove old rootfs if it exists
    if [ -d $CHROOTDIR ]; then
        info "Removing old rootfs..."
        rm -rf $CHROOTDIR
    fi
    mkdir -p $CHROOTDIR
    if [[ "$KEEPROOTFS" = "false" ]]; then
        rm -rf $ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz*
        # fetch and extract rootfs
        info "Downloading latest $ARCH rootfs..."
        cd $ROOTFS_IMG
        wget -q --show-progress --progress=bar:force:noscroll https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz
    fi
    #also fetch it, if it does not exist
    if [ ! -f "$ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz" ]; then
        cd $ROOTFS_IMG
        wget -q --show-progress --progress=bar:force:noscroll https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-$ARCH-latest.tar.gz
    fi
    
    info "Extracting $ARCH rootfs..."
    bsdtar -xpf $ROOTFS_IMG/Manjaro-ARM-$ARCH-latest.tar.gz -C $CHROOTDIR
    
    info "Setting up keyrings..."
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman-key --init || abort
    $NSPAWN $ROOTFS_IMG/rootfs_$ARCH pacman-key --populate archlinuxarm manjaro manjaro-arm || abort
    
    msg "Installing packages for eMMC installer edition of $EDITION on $DEVICE..."
    # Install device and editions specific packages
    echo "Server = $BUILDSERVER/arm-$BRANCH/\$repo/\$arch" > $CHROOTDIR/etc/pacman.d/mirrorlist
    mount -o bind $PKGDIR/pkg-cache $PKG_CACHE
    $NSPAWN $CHROOTDIR pacman -Syyu base manjaro-system manjaro-release manjaro-arm-emmc-flasher $PKG_EDITION $PKG_DEVICE --noconfirm

    info "Enabling services..."
    # Enable services
    $NSPAWN $CHROOTDIR systemctl enable getty.target 1> /dev/null 2>&1
    
    info "Setting up system settings..."
    # setting hostname
    echo "$HOSTNAME" | tee --append $ROOTFS_IMG/rootfs_$ARCH/etc/hostname 1> /dev/null 2>&1
    # enable autologin
    mv $CHROOTDIR/usr/lib/systemd/system/getty\@.service $CHROOTDIR/usr/lib/systemd/system/getty\@.service.bak
    cp $LIBDIR/getty\@.service $CHROOTDIR/usr/lib/systemd/system/getty\@.service
    
    if [ -f $IMGDIR/Manjaro-ARM-$EDITION-$DEVICE-$VERSION.img.xz ]; then
        info "Copying local $DEVICE $EDITION image..."
        cp $IMGDIR/Manjaro-ARM-$EDITION-$DEVICE-$VERSION.img.xz $CHROOTDIR/var/tmp/Manjaro-ARM.img.xz
        sync
    else
        info "Downloading $DEVICE $EDITION image..."
        cd $CHROOTDIR/var/tmp/
        wget -q --show-progress --progress=bar:force:noscroll -O Manjaro-ARM.img.xz https://github.com/manjaro-arm/$DEVICE-images/releases/download/$VERSION/Manjaro-ARM-$EDITION-$DEVICE-$VERSION.img.xz
    fi
    
    info "Cleaning rootfs for unwanted files..."
    prune_cache
    rm $CHROOTDIR/usr/bin/qemu-aarch64-static
    rm -rf $CHROOTDIR/var/log/*
    rm -rf $CHROOTDIR/etc/*.pacnew
    rm -rf $CHROOTDIR/usr/lib/systemd/system/systemd-firstboot.service
    rm -rf $CHROOTDIR/etc/machine-id
}

create_img_halium() {
	msg "Finishing image for $DEVICE $EDITION edition..."
    info "Creating image..."

    ARCH='aarch64'

    SIZE=$(du -s --block-size=MB $CHROOTDIR | awk '{print $1}' | sed -e 's/MB//g')
    EXTRA_SIZE=300
    REAL_SIZE=`echo "$(($SIZE+$EXTRA_SIZE))"`

    #making blank .img to be used
    dd if=/dev/zero of=$IMGDIR/$IMGNAME.img bs=1M count=$REAL_SIZE 1> /dev/null 2>&1

    #format it
    mkfs.ext4 $IMGDIR/$IMGNAME.img -L ROOT_MNJRO 1> /dev/null 2>&1
	info "Copying files to image..."
    mkdir -p $TMPDIR/root
    mount $IMGDIR/$IMGNAME.img $TMPDIR/root
    cp -ra $ROOTFS_IMG/rootfs_$ARCH/* $TMPDIR/root/

    umount $TMPDIR/root/
    rm -r $TMPDIR/root/
    
    chmod 666 $IMGDIR/$IMGNAME.img
}

create_img() {
    msg "Finishing image for $DEVICE $EDITION edition..."
    info "Creating partitions..."

    ARCH='aarch64'
    
    SIZE=$(du -s --block-size=MB $CHROOTDIR | awk '{print $1}' | sed -e 's/MB//g')
    EXTRA_SIZE=600
    REAL_SIZE=`echo "$(($SIZE+$EXTRA_SIZE))"`
    
    #making blank .img to be used
    dd if=/dev/zero of=$IMGDIR/$IMGNAME.img bs=1M count=$REAL_SIZE 1> /dev/null 2>&1

    #probing loop into the kernel
    modprobe loop 1> /dev/null 2>&1

    #set up loop device
    LDEV=`losetup -f`
    DEV=`echo $LDEV | cut -d "/" -f 3`

    #mount image to loop device
    losetup $LDEV $IMGDIR/$IMGNAME.img 1> /dev/null 2>&1

    case "$FILESYSTEM" in
        btrfs)
            # Create partitions
            #Clear first 32mb
            dd if=/dev/zero of=${LDEV} bs=1M count=32 1> /dev/null 2>&1
            #partition with boot and root
            case "$DEVICE" in
                oc2|on2|on2-plus|oc4|ohc4|vim1|vim2|vim3|radxa-zero|radxa-zero2|gtking-pro|gsking-x|rpi3|rpi4|pinephone)
                    parted -s $LDEV mklabel msdos 1> /dev/null 2>&1
                    ;;
                quartz64-bsp)
                    parted -s $LDEV mklabel gpt 1> /dev/null 2>&1
                    parted -s $LDEV mkpart uboot fat32 8MiB 16MiB 1> /dev/null 2>&1
                    parted -s $LDEV mkpart primary fat32 32M 256M 1> /dev/null 2>&1
                    START=`cat /sys/block/$DEV/${DEV}p2/start`
                    SIZE=`cat /sys/block/$DEV/${DEV}p2/size`
                    END_SECTOR=$(expr $START + $SIZE)
                    parted -s $LDEV mkpart primary btrfs "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                    parted -s $LDEV set 2 esp on
                    partprobe $LDEV 1> /dev/null 2>&1
                    mkfs.vfat "${LDEV}p2" -n BOOT_MNJRO 1> /dev/null 2>&1
                    mkfs.btrfs -m single -L ROOT_MNJRO "${LDEV}p3" 1> /dev/null 2>&1
                
                    #copy rootfs contents over to the FS
                    info "Creating subvolumes..."
                    mkdir -p $TMPDIR/root
                    mkdir -p $TMPDIR/boot
                    mount ${LDEV}p2 $TMPDIR/boot
                    # Do subvolumes
                    mount -o compress=zstd "${LDEV}p3" $TMPDIR/root
                    btrfs su cr $TMPDIR/root/@ 1> /dev/null 2>&1
                    btrfs su cr $TMPDIR/root/@home 1> /dev/null 2>&1
                    umount $TMPDIR/root
                    mount -o compress=zstd,subvol=@ "${LDEV}p3" $TMPDIR/root
                    mkdir -p $TMPDIR/root/home
                    mount -o compress=zstd,subvol=@home "${LDEV}p3" $TMPDIR/root/home
                    info "Copying files to image..."
                    cp -ra $ROOTFS_IMG/rootfs_$ARCH/* $TMPDIR/root/
                    mv $TMPDIR/root/boot/* $TMPDIR/boot/
                    ;;
                *)
                    parted -s $LDEV mklabel gpt 1> /dev/null 2>&1
                    ;;
            esac
            if [[ "$DEVICE" != "quartz64-bsp" ]]; then
                parted -s $LDEV mkpart primary fat32 32M 256M 1> /dev/null 2>&1
                if [[ "$DEVICE" = "generic" ]]; then
                    parted -s $LDEV mkpart primary fat32 0% 256M 1> /dev/null 2>&1
                fi
                START=`cat /sys/block/$DEV/${DEV}p1/start`
                SIZE=`cat /sys/block/$DEV/${DEV}p1/size`
                END_SECTOR=$(expr $START + $SIZE)
                parted -s $LDEV mkpart primary btrfs "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                if [[ "$DEVICE" = "jetson-nano" ]]; then
                    parted -s $LDEV set 1 esp on
                fi
                partprobe $LDEV 1> /dev/null 2>&1
                mkfs.vfat "${LDEV}p1" -n BOOT_MNJRO 1> /dev/null 2>&1
                mkfs.btrfs -m single -L ROOT_MNJRO "${LDEV}p2" 1> /dev/null 2>&1
    
                #copy rootfs contents over to the FS
                info "Creating subvolumes..."
                mkdir -p $TMPDIR/root
                mkdir -p $TMPDIR/boot
                mount ${LDEV}p1 $TMPDIR/boot
                # Do subvolumes
                mount -o compress=zstd "${LDEV}p2" $TMPDIR/root
                btrfs su cr $TMPDIR/root/@ 1> /dev/null 2>&1
                btrfs su cr $TMPDIR/root/@home 1> /dev/null 2>&1
                umount $TMPDIR/root
                mount -o compress=zstd,subvol=@ "${LDEV}p2" $TMPDIR/root
                mkdir -p $TMPDIR/root/home
                mount -o compress=zstd,subvol=@home "${LDEV}p2" $TMPDIR/root/home
                info "Copying files to image..."
                cp -ra $ROOTFS_IMG/rootfs_$ARCH/* $TMPDIR/root/
                mv $TMPDIR/root/boot/* $TMPDIR/boot
            fi
            ;;
        *)
            # Create partitions
            #Clear first 32mb
            dd if=/dev/zero of=${LDEV} bs=1M count=32 1> /dev/null 2>&1
            #partition with boot and root
            case "$DEVICE" in
                oc2|on2|on2-plus|oc4|ohc4|vim1|vim2|vim3|radxa-zero|radxa-zero2|gtking-pro|gsking-x|rpi3|rpi4|pinephone)
                    parted -s $LDEV mklabel msdos 1> /dev/null 2>&1
                    ;;
                quartz64-bsp)
                    parted -s $LDEV mklabel gpt 1> /dev/null 2>&1
                    parted -s $LDEV mkpart uboot fat32 8M 16M 1> /dev/null 2>&1
                    parted -s $LDEV mkpart primary fat32 32M 256M 1> /dev/null 2>&1
                    START=`cat /sys/block/$DEV/${DEV}p2/start`
                    SIZE=`cat /sys/block/$DEV/${DEV}p2/size`
                    END_SECTOR=$(expr $START + $SIZE)
                    parted -s $LDEV mkpart primary ext4 "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                    parted -s $LDEV set 2 esp on
                    partprobe $LDEV 1> /dev/null 2>&1
                    mkfs.vfat "${LDEV}p2" -n BOOT_MNJRO 1> /dev/null 2>&1
                    mkfs.ext4 -O ^metadata_csum,^64bit "${LDEV}p3" -L ROOT_MNJRO 1> /dev/null 2>&1
                    info "Copying files to image..."
                    mkdir -p $TMPDIR/root
                    mkdir -p $TMPDIR/boot
                    mount ${LDEV}p2 $TMPDIR/boot
                    mount ${LDEV}p3 $TMPDIR/root
                    cp -ra $ROOTFS_IMG/rootfs_$ARCH/* $TMPDIR/root/
                    mv $TMPDIR/root/boot/* $TMPDIR/boot/
                    ;;
                *)
                    parted -s $LDEV mklabel gpt 1> /dev/null 2>&1
                    ;;
            esac
                if [[ "$DEVICE" != "quartz64-bsp" ]]; then
                    parted -s $LDEV mkpart primary fat32 32M 256M 1> /dev/null 2>&1
                    if [[ "$DEVICE" = "generic" ]]; then
                        parted -s $LDEV mkpart primary fat32 0% 256M 1> /dev/null 2>&1
                    fi
                    START=`cat /sys/block/$DEV/${DEV}p1/start`
                    SIZE=`cat /sys/block/$DEV/${DEV}p1/size`
                    END_SECTOR=$(expr $START + $SIZE)
                    parted -s $LDEV mkpart primary ext4 "${END_SECTOR}s" 100% 1> /dev/null 2>&1
                    if [[ "$DEVICE" = "jetson-nano" ]]; then
                        parted -s $LDEV set 1 esp on
                    fi
                    partprobe $LDEV 1> /dev/null 2>&1
                    mkfs.vfat "${LDEV}p1" -n BOOT_MNJRO 1> /dev/null 2>&1
                    mkfs.ext4 -O ^metadata_csum,^64bit "${LDEV}p2" -L ROOT_MNJRO 1> /dev/null 2>&1

                    #copy rootfs contents over to the FS
                    info "Copying files to image..."
                    mkdir -p $TMPDIR/root
                    mkdir -p $TMPDIR/boot
                    mount ${LDEV}p1 $TMPDIR/boot
                    mount ${LDEV}p2 $TMPDIR/root
                    cp -ra $ROOTFS_IMG/rootfs_$ARCH/* $TMPDIR/root/
                    mv $TMPDIR/root/boot/* $TMPDIR/boot
                fi
            ;;
    esac
        
    # Flash bootloader
    if [[ "$DEVICE" != "generic" ]]; then
    info "Flashing bootloader..."
    case "$DEVICE" in
    # AMLogic uboots
        oc2)
            dd if=$TMPDIR/boot/bl1.bin.hardkernel of=${LDEV} conv=fsync bs=1 count=442 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/bl1.bin.hardkernel of=${LDEV} conv=fsync bs=512 skip=1 seek=1 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/u-boot.gxbb of=${LDEV} conv=fsync bs=512 seek=97 1> /dev/null 2>&1
            ;;
        on2|on2-plus|oc4|ohc4)
            dd if=$TMPDIR/boot/u-boot.bin of=${LDEV} conv=fsync,notrunc bs=512 seek=1 1> /dev/null 2>&1
            ;;
        vim1|vim2|vim3|radxa-zero|radxa-zero2|gtking-pro|gsking-x)
            dd if=$TMPDIR/boot/u-boot.bin of=${LDEV} conv=fsync,notrunc bs=442 count=1 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/u-boot.bin of=${LDEV} conv=fsync,notrunc bs=512 skip=1 seek=1 1> /dev/null 2>&1
            ;;
        # Allwinner uboots
        pinebook|pine64-lts|pine64|pinetab|pine-h64)
            dd if=$TMPDIR/boot/u-boot-sunxi-with-spl-$DEVICE.bin of=${LDEV} conv=fsync bs=128k seek=1 1> /dev/null 2>&1
            ;;
        pinephone)
            dd if=$TMPDIR/boot/u-boot-sunxi-with-spl-$DEVICE-528.bin of=${LDEV} conv=fsync bs=8k seek=1 1> /dev/null 2>&1
            ;;
        # Rockchip RK33XX and RK35XX mainline uboots
        pbpro|rockpro64|rockpi4b|rockpi4c|nanopc-t4|rock64|roc-cc|stationp1|pinephonepro|clockworkpi-a06|quartz64-a|rock3a|pinenote|edgev|station-m2|station-p2)
            dd if=$TMPDIR/boot/idbloader.img of=${LDEV} seek=64 conv=notrunc,fsync 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/u-boot.itb of=${LDEV} seek=16384 conv=notrunc,fsync 1> /dev/null 2>&1
            ;;
        pbpro-bsp)
            dd if=$TMPDIR/boot/idbloader.img of=${LDEV} seek=64 conv=notrunc,fsync 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/uboot.img of=${LDEV} seek=16384 conv=notrunc,fsync 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/trust.img of=${LDEV} seek=24576 conv=notrunc,fsync 1> /dev/null 2>&1
            ;;
        # Rockchip RK35XX uboots
        quartz64-bsp)
            dd if=$TMPDIR/boot/idblock.bin of=${LDEV} seek=64 conv=notrunc,fsync 1> /dev/null 2>&1
            dd if=$TMPDIR/boot/uboot.img of=${LDEV}p1 conv=notrunc,fsync 1> /dev/null 2>&1
            ;;
    esac
    fi
    
    info "Writing PARTUUIDs..."
    if [[ "$DEVICE" = "quartz64-bsp" ]]; then
        BOOT_PART=$(lsblk -p -o NAME,PARTUUID | grep "${LDEV}p2" | awk '{print $2}')
        ROOT_PART=$(lsblk -p -o NAME,PARTUUID | grep "${LDEV}p3" | awk '{print $2}')
    else
        BOOT_PART=$(lsblk -p -o NAME,PARTUUID | grep "${LDEV}p1" | awk '{print $2}')
        ROOT_PART=$(lsblk -p -o NAME,PARTUUID | grep "${LDEV}p2" | awk '{print $2}')
    fi
    echo "Boot PARTUUID is $BOOT_PART..."
    sed -i "s/LABEL=BOOT_MNJRO/PARTUUID=$BOOT_PART/g" $TMPDIR/root/etc/fstab
    echo "Root PARTUUID is $ROOT_PART..."
    if [ -f $TMPDIR/boot/extlinux/extlinux.conf ]; then
        sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/extlinux/extlinux.conf
        elif [ -f $TMPDIR/boot/efi/extlinux/extlinux.conf ]; then
            sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/efi/extlinux/extlinux.conf
        elif [ -f $TMPDIR/boot/boot.ini ]; then
            sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/boot.ini
        elif [ -f $TMPDIR/boot/uEnv.ini ]; then
            sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/uEnv.ini
        #elif [ -f $TMPDIR/boot/cmdline.txt ]; then
        #    sed -i "s/PARTUUID=/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/cmdline.txt
        #elif [ -f $TMPDIR/boot/boot.txt ]; then
        #   sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/boot/boot.txt
        #   cd $TMPDIR/boot
        #   ./mkscr
        #   cd $HOME
    fi
    
    if [[ "$DEVICE" = "rpi4" ]] && [[ "$FILESYSTEM" = "btrfs" ]]; then
        echo "===> Installing default btrfs RPi cmdline.txt /boot..."
        echo "rootflags=subvol=@ root=PARTUUID=$ROOT_PART rw rootwait console=serial0,115200 console=tty3 selinux=0 quiet splash plymouth.ignore-serial-consoles smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 kgdboc=serial0,115200 usbhid.mousepoll=8 audit=0" >  $TMPDIR/boot/cmdline.txt
    elif [[ "$DEVICE" = "rpi4" ]]; then
        echo "===> Installing default ext4 RPi cmdline.txt /boot..."
        echo "root=PARTUUID=$ROOT_PART rw rootwait console=serial0,115200 console=tty3 selinux=0 quiet splash plymouth.ignore-serial-consoles smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 kgdboc=serial0,115200 usbhid.mousepoll=8 audit=0" >  $TMPDIR/boot/cmdline.txt
    fi
    if [[ "$DEVICE" = "rpi4" ]]; then
        echo "===> Installing default config.txt file to /boot/..."
        echo "# See /boot/overlays/README for all available options" > $TMPDIR/boot/config.txt
        echo "" >> $TMPDIR/boot/config.txt
        echo "#gpu_mem=64" >> $TMPDIR/boot/config.txt
        echo "initramfs initramfs-linux.img followkernel" >> $TMPDIR/boot/config.txt
        echo "kernel=kernel8.img" >> $TMPDIR/boot/config.txt
        echo "arm_64bit=1" >> $TMPDIR/boot/config.txt
        echo "disable_overscan=1" >> $TMPDIR/boot/config.txt
        echo "" >> $TMPDIR/boot/config.txt
        echo "#enable sound" >> $TMPDIR/boot/config.txt
        echo "dtparam=audio=on" >> $TMPDIR/boot/config.txt
        echo "#hdmi_drive=2" >> $TMPDIR/boot/config.txt
        echo "" >> $TMPDIR/boot/config.txt
        echo "#enable vc4" >> $TMPDIR/boot/config.txt
        echo "dtoverlay=vc4-fkms-v3d" >> $TMPDIR/boot/config.txt
        echo "max_framebuffers=2"  >> $TMPDIR/boot/config.txt
        echo "disable_splash=1" >> $TMPDIR/boot/config.txt
    fi
    
    if [[ "$FILESYSTEM" = "btrfs" ]]; then
        sed -i "s/LABEL=ROOT_MNJRO/PARTUUID=$ROOT_PART/g" $TMPDIR/root/etc/fstab
    else
        echo "PARTUUID=$ROOT_PART   /   $FILESYSTEM     defaults    0   1" >> $TMPDIR/root/etc/fstab
    fi
    
    
    # Clean up
    info "Cleaning up image..."
    if [[ "$FILESYSTEM" = "btrfs" ]]; then
        umount $TMPDIR/root/home
    fi
    umount $TMPDIR/root
    umount $TMPDIR/boot
    losetup -d $LDEV 1> /dev/null 2>&1
    rm -r $TMPDIR/root $TMPDIR/boot
    partprobe $LDEV 1> /dev/null 2>&1
    chmod 666 $IMGDIR/$IMGNAME.img
}

create_bmap() {
    if [ ! -e /usr/bin/bmaptool ]; then
        echo "'bmap-tools' are not installed. Skipping."
    else
        info "Creating bmap."
        cd ${IMGDIR}
        rm ${IMGNAME}.img.bmap 2>/dev/null
        bmaptool create -o ${IMGNAME}.img.bmap ${IMGNAME}.img
    fi
}

compress() {
    if [ -f $IMGDIR/$IMGNAME.img.xz ]; then
        info "Removing existing compressed image file {$IMGNAME.img.xz}..."
        rm -rf $IMGDIR/$IMGNAME.img.xz
    fi
    info "Compressing $IMGNAME.img..."
    #compress img
    cd $IMGDIR
    xz -zv --threads=0 $IMGNAME.img
    chmod 666 $IMGDIR/$IMGNAME.img.xz

    info "Removing rootfs_$ARCH"
    mount | grep "$ROOTFS_IMG/rootfs_$ARCH/var/cache/pacman/pkg" 1> /dev/null 2>&1
    STATUS=$?
    [ $STATUS -eq 0 ] && umount $ROOTFS_IMG/rootfs_$ARCH/var/cache/pacman/pkg
    rm -rf $CHROOTDIR
}

build_pkg() {
    # Install local package to rootfs before building
    if [[ ! -z "$ADD_PACKAGE" ]]; then
        installLocalPackage
        # The list of packages is generated in installLocalPackage()
        $NSPAWN $CHROOTDIR pacman -U $listForPacman --noconfirm
        if [[ $? != 0 ]]; then
            echo -e "ERROR:\nThere was a problem with installing the local package/s.\nPlease,check the logs."
            exit 1 # TODO: Verify that the exit will be clean
        fi
    fi
    # Build the actual package
    msg "Copying build directory {$PACKAGE} to rootfs..."
    $NSPAWN $CHROOTDIR mkdir build 1> /dev/null 2>&1
    mount -o bind "$PACKAGE" $CHROOTDIR/build
    msg "Building {$PACKAGE}..."
    mount -o bind $PKGDIR/pkg-cache $PKG_CACHE
    $NSPAWN $CHROOTDIR pacman -Syu 1> /dev/null 2>&1
    if [[ $INSTALL_NEW = true ]]; then
        $NSPAWN $CHROOTDIR --chdir=/build/ makepkg -Asci --noconfirm
    else
        $NSPAWN $CHROOTDIR --chdir=/build/ makepkg -Asc --noconfirm
    fi
}

export_and_clean() {
    if ls $CHROOTDIR/build/*.pkg.tar.* 1> /dev/null 2>&1; then
        #pull package out of rootfs
        msg "Package Succeeded..."
        info "Extracting finished package out of rootfs..."
        mkdir -p $PKGDIR/$ARCH
        cp $CHROOTDIR/build/*.pkg.tar.* $PKGDIR/$ARCH/
        chown -R $SUDO_USER $PKGDIR
        msg "Package saved as {$PACKAGE} in {$PKGDIR/$ARCH}..."
        umount $CHROOTDIR/build

        #clean up rootfs
        info "Cleaning build files from rootfs"
        rm -rf $CHROOTDIR/build/
    else
        msg "!!!!! Package failed to build !!!!!"
        umount $CHROOTDIR/build
        prune_cache
        rm -rf $CHROOTDIR/build/
        exit 1
    fi
}

clone_profiles() {
    cd $PROFILES
    git clone --branch $1 https://gitlab.manjaro.org/manjaro-arm/applications/arm-profiles.git
}

get_profiles() {
    local branch=master
    if ls $PROFILES/arm-profiles/* 1> /dev/null 2>&1; then
        if [[ $(grep branch $PROFILES/arm-profiles/.git/config | cut -d\" -f2) = "$branch" ]]; then
            cd $PROFILES/arm-profiles
            git pull
        else
            rm -rf $PROFILES/arm-profiles/
            clone_profiles $branch
        fi
    else
        clone_profiles $branch
    fi
}

verifyLocalPackage() {
    readarray -td, packages <<<$ADD_PACKAGE; declare -p packages; > /dev/null 2>&1
      
    # Check if file exists
    for package in "${packages[@]}"
    do 
        packageToAdd="$package"
        if [ -f $packageToAdd ]; then
            echo "File found: $packageToAdd"

            # Test if it is a tar archive
            tar tf ${packageToAdd//[$'\n']} > /dev/null 2>&1
            if [[ $? != 0 ]]; then
                echo "$packageToAdd is not a valid tar archive"
                exit 1
            fi

            # Check if the tar contains .BUILDINFO and architecture
            # Temp file to extract
            tar --use-compress-program=unzstd -xf "${packageToAdd//[$'\n']}" ".BUILDINFO" > /dev/null 2>&1
            if [[ $? != 0 ]]; then
                echo -e "ERROR:\n${packageToAdd//[$'\n']} is NOT a valid package\nNo .BUILDINFO found"
                exit 1
            fi 

            verifyPackageArch=$(grep "pkgarch" $PWD/.BUILDINFO | head -1)

            if [ -f "$PWD/.BUILDINFO" ]; then
                if [[ $verifyPackageArch == *"aarch64"* || $verifyPackageArch == *"any"* ]]; then
                    echo "${packageToAdd//[$'\n']} is compatible with aarch64"
                else
                    echo -e "ERROR:\n${packageToAdd//[$'\n']} - NOT compatible with aarch64"
                    rm "$PWD/.BUILDINFO"
                    exit 1
                fi
                # Cleanup
                rm "$PWD/.BUILDINFO"
            else
                echo -e "ERROR:\n${packageToAdd//[$'\n']} - couldn't find the local copy .BUILDINFO file"
                exit 1
            fi   
        else
            echo -e "ERROR:\nCan't find such file: ${packageToAdd//[$'\n']}"
            exit 1
        fi
    done
}

installLocalPackage() {
    info "Installing local package {$ADD_PACKAGE} to rootfs..."
        
        readarray -td, packages <<<$ADD_PACKAGE; declare -p packages; > /dev/null 2>&1
        
        declare -a finalPackages=()
        i=0

        for package in "${packages[@]}"
        do
        	packageToAdd="$package"

            # Simplistic path manipulation	
        	if [[ $packageToAdd == *"/"* ]]; then
        		packageToAdd="$packageToAdd"
        	else
        		packageToAdd="$PWD/$packageToAdd" 
        	fi

        	# Add the file path to the final array
        	if [ -f $packageToAdd ]; then 
        		finalPackages[$i]=$packageToAdd
        		((++i))
            else 
        	    echo -e "ERROR:\nCan't find such file: ${packageToAdd//[$'\n']}" 
        		exit 1
        	fi
        done

        listForPacman=""

        # List all packages to add
        echo -e "\nList of packages to add:"

        for package in "${finalPackages[@]}"
        do
            echo "${package//[$'\n']}"
            cp -ap $package $PKG_CACHE/
            listForPacman+="/var/cache/pacman/pkg/${package##*/} "
        done
}
