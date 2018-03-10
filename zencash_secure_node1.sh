#!/usr/bin/env bash

# IMPORTANT: Run this script from /home/<USER>/ directory: bash -c "$(curl SCRIPT_URL)"


# (optional): Preparing the environment if you want to install zen from source:
# Once you get the VM up and running you need to login with your root account and run below commands.
# apt-get update && apt-get upgrade -y
# apt-get install -y build-essential pkg-config libc6-dev m4 g++-multilib autoconf libtool ncurses-dev unzip git python zlib1g-dev wget bsdmainutils automake libgtk2.0-dev && apt-get autoremove -y

# If there is nothing in crontab after running this script then:
# 1) crontab -e
# 2) add: @reboot /usr/bin/zend
# 3) add: 6 0 * * * "/home/<VM_USERNAME>/.acme.sh"/acme.sh --cron --home "/home/<VM_USERNAME>/.acme.sh" > /dev/null

# Quit on any error.
set -e
purpleColor='\033[0;95m'
normalColor='\033[0m'

# Set environment variables:
read -p "Enter Host Name (a.example.com): " HOST_NAME
if [[ $HOST_NAME == "" ]]; then
  echo "HOST name is required!"
  exit 1
fi

# zen installation method:
#DEFAULT="1"
#read -p "Enter 1 to build ZEN from repo; enter 2 to build from source: (default 1)" ZEN_INSTALL_CHOICE
#ZEN_INSTALL_CHOICE="${ZEN_INSTALL_CHOICE:-${DEFAULT}}"
ZEN_INSTALL_CHOICE=1

USER=$(whoami)

echo -e $purpleColor"Host name: $HOST_NAME\nUser name: $USER\nZen installation choice: $ZEN_INSTALL_CHOICE\n"$normalColor

################################################################# packages ##########################################################
sudo apt-get update
sudo apt -y install pwgen
sudo apt-get install git -y
sudo apt -y install fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

################################################################ basic security #####################################################
sudo ufw default allow outgoing
sudo ufw default deny incoming
sudo ufw allow ssh/tcp
sudo ufw limit ssh/tcp
sudo ufw allow http/tcp
sudo ufw allow https/tcp
sudo ufw allow 9033/tcp
sudo ufw allow 19033/tcp
sudo ufw logging on
sudo ufw --force enable
echo -e $purpleColor"Basic security completed!"$normalColor


################################################################# Add a swapfile. #####################################################
if [ $(cat /proc/swaps | wc -l) -lt 2 ]; then
  echo "Configuring your swapfile..."
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
sudo  echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
else
  echo "Swapfile exists. Skipping."
fi
echo -e $purpleColor"Swapfile is done!"$normalColor

#################################### Create an empty zen config file and add new config settings. ###################################
if [ -f /home/$USER/.zen/zen.conf ]; then
  sudo rm /home/$USER/.zen/zen.conf || true
fi
echo "Creating an empty ZenCash config..."
sudo mkdir -p /home/$USER/.zen || true
sudo touch /home/$USER/.zen/zen.conf

RPC_USERNAME=$(pwgen -s 16 1)
RPC_PASSWORD=$(pwgen -s 64 1)

sudo sh -c "echo '
addnode=$HOST_NAME
addnode=zennodes.network
rpcuser=$RPC_USERNAME
rpcpassword=$RPC_PASSWORD
rpcport=18231
rpcallowip=127.0.0.1
server=1
daemon=1
listen=1
txindex=1
logtimestamps=1
# ssl
tlscertpath=/home/$USER/.acme.sh/$HOST_NAME/$HOST_NAME.cer
tlskeypath=/home/$USER/.acme.sh/$HOST_NAME/$HOST_NAME.key
### testnet config
testnet=0
' >> /home/$USER/.zen/zen.conf"

echo -e $purpleColor"zen.conf is done!"$normalColor


############################################################### ssl-certificate: ####################################################
if [ ! -d /home/$USER/acme.sh ]; then
  sudo apt install socat
  cd /home/$USER && git clone https://github.com/Neilpang/acme.sh.git
  cd /home/$USER/acme.sh && sudo ./acme.sh --install
  sudo chown -R $USER:$USER /home/$USER/.acme.sh
fi
if [ ! -f /home/$USER/.acme.sh/$HOST_NAME/ca.cer ]; then
  sudo /home/$USER/.acme.sh/acme.sh --issue --standalone -d $HOST_NAME
fi
cd ~
sudo cp /home/$USER/.acme.sh/$HOST_NAME/ca.cer /usr/local/share/ca-certificates/$HOST_NAME.crt
sudo update-ca-certificates
CRONCMD_ACME="6 0 * * * \"/home/$USER/.acme.sh\"/acme.sh --cron --home \"/home/$USER/.acme.sh\" > /dev/null" && (crontab -l | grep -v -F "$CRONCMD_ACME" ; echo "$CRONCMD_ACME") | crontab -
echo -e $purpleColor"certificates has been installed!"$normalColor


############################################################ Installing zen: ##########################################################
case $ZEN_INSTALL_CHOICE in
  1)
     echo "BUILD FROM REPO:"
     if ! [ -x "$(command -v zend)" ]; then
       sudo apt-get install apt-transport-https lsb-release -y
       echo 'deb https://zencashofficial.github.io/repo/ '$(lsb_release -cs)' main' | sudo tee --append /etc/apt/sources.list.d/zen.list
       gpg --keyserver ha.pool.sks-keyservers.net --recv 219F55740BBF7A1CE368BA45FB7053CE4991B669
       gpg --export 219F55740BBF7A1CE368BA45FB7053CE4991B669 | sudo apt-key add -
       
       sudo apt-get update
       sudo apt-get install zen -y
       
       sudo chown -R $USER:$USER /home/$USER/.zen
       zen-fetch-params
     fi
  ;;
  2)
    echo "BUILD FROM SOURCE:"
    if ! [ -x "$(command -v /home/$USER/zen/src/zend)" ]; then
      # Clone ZenCash from Git repo.
      if [ -d /home/$USER/zen ]; then
        sudo rm -r /home/$USER/zen
      fi
      echo "Downloading ZenCash source..."
      git clone https://github.com/ZencashOfficial/zen.git
      
      # Download proving keys.
      if [ ! -f /home/$USER/.zcash-params/sprout-proving.key ]; then
        echo "Downloading ZenCash keys..."
        sudo /home/$USER/zen/zcutil/fetch-params.sh
      fi
      
      # Compile source.
      echo -e $purpleColor"Compiling ZenCash..."$normalColor
      cd /home/$USER/zen && ./zcutil/build.sh -j$(nproc)
      sudo chown -R $USER:$USER /home/$USER/.zen
      
      # copy executable to the bin directory.
      sudo cp /home/$USER/zen/src/zend /usr/bin/
      sudo cp /home/$USER/zen/src/zen-cli /usr/bin/
    fi
  ;;
  *)
    echo "Invalid choice to install zen. Re-run the script!"
    exit 1
  ;;
esac

echo -e $purpleColor"zen installation is finished!"$normalColor


########################################### run znode and sync chain on startup of VM: ##############################################

CRONCMD="@reboot /usr/bin/zend" && (crontab -l | grep -v -F "$CRONCMD" ; echo "$CRONCMD") | crontab -

####################################################### secnodetracker #############################################################
sudo apt -y install npm
sudo npm install -g n
sudo n latest
sudo npm install pm2 -g
if [ ! -d /home/$USER/secnodetracker ]; then
  cd /home/$USER && git clone https://github.com/ZencashOfficial/secnodetracker.git
  cd /home/$USER/secnodetracker && npm install
fi
echo -e $purpleColor"secnodetracker added!"$normalColor


# Done.
#################################################### Useful commands #############################################################
echo ""
echo ""
echo "Now type \"~/zen/src/zend\" or \"zend\" to launch ZenCash!"
echo "\n"
echo "Check totalbalance: zen-cli z_gettotalbalance"
echo "\n"
echo "Get new address: zen-cli z_getnewaddress"
echo "\n"
echo "List all addresses: zen-cli z_listaddresses"
echo "\n"
echo "Get network info: zen-cli getnetworkinfo. Make sure 'tls_cert_verified' is true."
echo "\n"
echo "###############################################################################################################"
echo "\n"
echo "Deposit 5 x 0.2 ZEN in private address within VPS"
echo "\n"
echo "Run app from /home/$USER/secnodetracker/ directory: \"node setup.js\" and \"node app.js\""
echo "\n"
echo "ALL DONE! "
echo ""
echo ""