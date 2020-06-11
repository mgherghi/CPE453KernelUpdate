
#!/bin/bash
# p01.sh
# Gherghina, Mihai

# Took me a while but I did this so that i could splice up
# the input one at a time

# for checking swapfile ######################################################
FILE=/swapfile
################################################################################

# Pesky Dracut file ############################################################
DRACUT=/etc/dracut.conf.d/xen.conf
################################################################################

# apps to check for install ####################################################
pckarr=( autoconf automake binutils bison flex gcc gcc-c++ gdb glibc-devel \ libtool make pkgconf pkgconf-m4 pkgconf-pkg-config redhat-rpm-config \ rpm-build rpm-sign strace asciidoc byacc ctags diffstat git intltool ltrace \ patchutils perl-Fedora-VSP perl-generators pesign source-highlight \
systemtap valgrind valgrind-devel cmake expect rpmdevtools rpmlint \
jq wget perl ncurses-devel make gcc bc bison flex elfutils-libelf-devel \ openssl-devel )
################################################################################

# for checking swapfile ######################################################
GPGKEYS=~/.gnupg
################################################################################

# check installed kernel #######################################################
InstalledKernel=$(uname -r) # check installed kernel
################################################################################

# install dependencies #########################################################
sudo yum update -y -q
for i in  ${pckarr[*]}
 do
  isinstalled=$(rpm -q $i)
  if [ !  "$isinstalled" == "package $i is not installed" ]; then
    :
  else
    sudo yum install $i -y -q
  fi
done
################################################################################

#Checks against mainline version ###############################################
V=$(curl -s https://www.kernel.org/releases.json | \
    jq '.latest_stable.version' -r)

M="$(echo $(curl -s https://www.kernel.org/releases.json | \
    jq '.latest_stable.version' -r)  \
    | cut -d. -f1)"
################################################################################

##########################################################
POSITIONAL=()
for i in "$@"
do
key="$1"
    case $key in
        -g) Git=true
            shift # past argument
            ;;
        -v) Version=true
            shift # past argument
            ;;
        -h) Help=true
            shift # past argument
            ;;
        -R) Reboot=true
            shift # past argument
            ;;
        -D) Dir=true
            TargetDir="$2"
            shift
            ;;
        *)  POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
################################################################################

################################################################################
if [[ $Help && $Version ]]; then
    echo "p01 - install current linux stable kernel
    Installs current linux stable kernel source code into given Subdir
    or ~/src/linux-stable by default.  p01 takes a number of options,
    as described below.
    -g         git clone source from kernel.org instead of wget or curl
    -v         Version of new stable kernel but does not install it.
    -h         Help should display options with examples.
    -R         Reboot after download and install.
    -D Subdir  Subdir is the fullpath of downloaded stable kernel source
    "
    exit 0
elif [[ $Help ]]; then
    echo "p01 - install current linux stable kernel
    Installs current linux stable kernel source code into given Subdir
    or ~/src/linux-stable by default.  p01 takes a number of options,
    as described below.
    -g         git clone source from kernel.org instead of wget or curl
    -v         Version of new stable kernel but does not install it.
    -h         Help should display options with examples.
    -R         Reboot after download and install.
    -D Subdir  Subdir is the fullpath of downloaded stable kernel source
    "
    exit 0
else
    echo ""
fi
################################################################################


# check to see if kernel is already installed ##################################
if [[ $InstalledKernel == $V ]]; then
    echo "linux-stable already installed"
    echo ""
    exit 1
fi
################################################################################

# Checks latest Version ########################################################
if [[ $Version ]]; then
    echo ""
    echo 'Latest Stable Kernel Version is : '
    echo $(curl -s https://www.kernel.org/releases.json | \
    jq '.latest_stable.version' -r)
    echo ""
    exit 0
fi
################################################################################

#Checks to see if -D is passed ################################################
if [[ $Dir ]]; then
    mkdir $TargetDir && cd $TargetDir
else
    TargetDir=$HOME/src/
    if [[ ! -d $TargetDir ]]; then
        mkdir ${TargetDir}
    else
        echo ""
    fi
fi
################################################################################

# Building the swap ############################################################
if [ ! -e $FILE ]; then
    sudo fallocate -l 550M /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
fi
################################################################################

# Dracut Check #################################################################
if [ -e $DRACUT ]; then
    sudo rm /etc/dracut.conf.d/xen.conf
fi
################################################################################

# check for ccache  ############################################################
if [[ $( ccache --version | grep -c 3.7.8 ) -lt 1 ]]; then
    cd $TargetDir
    wget "https://github.com/ccache/ccache/releases/download/v3.7.8/ccache-3.7.8.tar.xz"
    wget "https://github.com/ccache/ccache/releases/download/v3.7.8/ccache-3.7.8.tar.xz.asc"

    if [[ $(gpg --verify ccache-3.7.8.tar.xz.asc ccache-3.7.8.tar.xz 2>&1 \
        | grep -c "Good signature .* \[ultimate\]") -lt 1 ]]; then
        echo "Error: invalid source"
        exit 1
    else
        echo "Good Source"
    fi
    tar xvf ccache-3.7.8.tar
    cd $TargetDir/ccache-3.7.8
    ./configure
    make -j$(nproc)
    sudo make -j$(nproc) install
fi
################################################################################

#Hard coding the keys , thank you stackexchange ################################
if [ ! -d "$GPGKEYS" ]; then
    gpg2 --locate-keys "torvalds@kernel.org" "gregkh@kernel.org"
    for trusted in "torvalds@kernel.org" "gregkh@kernel.org"; do
        echo -e "5\ny\n" | gpg --command-fd 0 --expert --edit-key $trusted trust
    done
fi
################################################################################

#using the git method to download the kernel ###################################
if [[ $Git ]]; then
    #echo "git"
    cd $TargetDir
    git clone --branch v$V \
        'https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
    cd linux-stable

    if [[ $(git tag -v v$V 2>&1 \
        | grep -c "Good signature .* \[ultimate\]") -lt 1 ]]; then
        echo "Bad Source"
        exit 1
    else
        echo "Good Source"
    fi

    #sudo cp /boot/config-`uname -r` .config
    yes '' | ccache make -j2 localmodconfig
    ccache make -j$(nproc)
    ccache make -j$(nproc) modules
    sudo make -j$(nproc) modules_install
    sudo make -j$(nproc) install
else  #use wget to download kernel###########################################
    #echo "wget"
    cd $TargetDir
    wget "https://cdn.kernel.org/pub/linux/kernel/v${M}.x/linux-${V}.tar.xz"
    wget "https://cdn.kernel.org/pub/linux/kernel/v${M}.x/linux-${V}.tar.sign"
    xz -d -v linux-${V}.tar.xz

    if [[ $(gpg --verify linux-$V.tar.sign linux-$V.tar 2>&1 \
        | grep -c "Good signature .* \[ultimate\]") -lt 1 ]]; then
        echo "Bad Source"
        exit 1
    else
        echo "Good Source"
    fi

    tar xvf linux-${V}.tar
    sudo rm *.tar
    sudo rm *.sign
    cd linux-${V}
    echo ""
    sudo cp /boot/config-`uname -r` .config
    yes '' | ccache make -j$(nproc) localmodconfig
    echo ""
    ccache make -j$(nproc) 
    echo ""
    ccache make -j$(nproc) modules
    echo ""
    sudo make -j$(nproc) modules_install
    echo ""
    sudo make -j$(nproc) install
fi
################################################################################

# if -R is passed ##############################################################
if [[ $Reboot ]]; then
    sudo reboot
fi
################################################################################

exit 0  # exit on success
