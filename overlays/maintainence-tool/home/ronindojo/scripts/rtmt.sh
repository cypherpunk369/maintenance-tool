#!/bin/bash

SCRIPTHOME="/home/ronindojo/scripts" 

clear

#
# mount
#
if [ -d "/mnt/usb" ] 
then
    echo "" 
else
    mkdir /mnt/usb && mount /dev/nvme0n1p1 /mnt/usb
fi

#
# Text & color functions
#
red='\e[31m'
clear='\e[0m'

TextRed(){
        echo -ne $red$1$clear
}

#
# menu functions
#

# basic LED check
function led_check() {
    clear
    echo ""
    echo "Performing LED Functional Test"
    echo "Observe the flashing LEDs to confirm they are functional"
    sudo python "$SCRIPTHOME"/GPIO/LED.check.py
    sudo bash -c "$SCRIPTHOME"/rtmt.sh
    clear
}

# delete data exclusive blockchain data
function del_data_excl() {
    clear
    echo ""
    echo "$(TextRed 'CAUTION!!! THIS ACTION WILL EREASE DATA!!!')"
    echo "$(TextRed 'This action will erase the following data from backup directory on the hard drive:')"
    echo "$(TextRed '- Dojo')"
    echo "$(TextRed '- Docker')"
    echo "$(TextRed '- Indexer')"
    echo "$(TextRed '- Tor')"
    echo ""

    read -p "Do you wish to continue? (y/n): " prompt
    if [[ "$prompt" == "y" ]]; then
       sudo rm -rf /mnt/usb/backup/{dojo,docker,indexer,tor}
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.on.py
       sleep 2
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.off.py
       sudo ls -la /mnt/usb/backup
       echo ""
       echo "$(TextRed 'This action was successful')" 
       echo ""
       echo "$(TextRed 'Press any key to continue')"
       read -n 1 -r -s
       sudo bash -c "$SCRIPTHOME"/rtmt.sh
       clear
    else
       echo ""
       clear
fi

}

# delete all data
function del_data_incl() {
    clear
    echo ""
    echo "$(TextRed 'CAUTION!!!')"
    echo "$(TextRed 'This action will erase the following data from backup directory on the hard drive:')"
    echo "$(TextRed '- Dojo')"
    echo "$(TextRed '- Docker')"
    echo "$(TextRed '- Indexer')"
    echo "$(TextRed '- Tor')"
    echo "$(TextRed '- Bitcoind (containing the IBD)')"
    echo ""

    read -p "Are you sure (y/n): " prompt
    if [[ "$prompt" == "y" ]]; then
       sudo rm -rf /mnt/usb/backup
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.on.py
       sleep 2
       sudo python ~/scripts/GPIO/turn.LED.off.py
       sudo ls -la /mnt/usb/backup
       echo ""
       echo "$(TextRed 'This action was successful')" 
       echo ""
       echo "$(TextRed 'Press any key to continue')"
       read -n 1 -r -s
       sudo bash -c "$SCRIPTHOME"/rtmt.sh
       clear
    else
       echo ""
       clear
fi

}

# format 
function format_nvme() {
      clear
      echo ""
      echo "$(TextRed 'CAUTION!!!')"
      echo "$(TextRed 'This action will reformat the hard drive and wipe all data')"
      echo ""
      read -p "Do you wish to continue? (y/n): " prompt
      if [[ "$prompt" == "y" ]]; then
       sudo umount /mnt/usb
       sudo mkfs -t ext4 -F /dev/nvme0n1p1 && \
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.on.py
       sleep 2
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.off.py
       echo ""
       echo "$(TextRed 'This action was successful')" 
       echo ""
       echo "$(TextRed 'Press any key to continue')"
       read -n 1 -r -s
       sudo bash -c "$SCRIPTHOME"/rtmt.sh
       clear
      else
       echo ""
       clear
fi
}

# format 
function format_sda() {
      clear
      echo ""
      echo "$(TextRed 'CAUTION!!!')"
      echo "$(TextRed 'This action will reformat the hard drive and wipe all data')"
      echo ""
      read -p "Do you wish to continue? (y/n): " prompt
      if [[ "$prompt" == "y" ]]; then
       sudo umount /mnt/usb
       sudo mkfs -t ext4 -F /dev/sda1 && \
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.on.py
       sleep 2
       sudo python "$SCRIPTHOME"/GPIO/turn.LED.off.py
       echo ""
       echo "$(TextRed 'This action was successful')" 
       echo ""
       echo "$(TextRed 'Press any key to continue')"
       read -n 1 -r -s
       sudo bash -c "$SCRIPTHOME"/rtmt.sh
       clear
      else
       echo ""
       clear
fi
}

# shutdown
function shutdown() {
      clear
      echo ""
      echo "$(TextRed 'Shutdown?') "
      echo ""
      read -p "Are you sure (y/n): " prompt
      if [[ "$prompt" == "y" ]]; then
      sudo systemctl poweroff 
      else
         echo ""
fi
}


function tanto_checks() {
     led_check
     del_data_excl
     del_data_incl
     format_nvme
     format_sda
     shutdown
}

#
# menu
#
menu(){
echo -ne "
$(TextRed '#######################################################')
$(TextRed 'RoninDojo Tanto maintenance tool')
$(TextRed '#######################################################')

1) LED Functional Test
2) Delete Backup Data on Hard Drive - Excluding IBD
3) Delete Backup Data on Hard Drive - Including IBD
4) Format NVMe Hard Drive (Tanto, Tanto DIY)
5) Format SATA Hard Drive
6) Shutdown
7) Exit
Choose an option:"
        read a
        case $a in
	        1) led_check ; menu ;;
	        2) del_data_excl ; menu ;;
	        3) del_data_incl ; menu ;;
	        4) format_nvme ; menu ;;
                5) format_sda ; menu ;;
                6) shutdown ; menu ;;
		7) exit 0 ;;
		*) echo -e $red"Wrong option."$clear; WrongCommand;;
        esac
}

#
# call menu
#
menu

