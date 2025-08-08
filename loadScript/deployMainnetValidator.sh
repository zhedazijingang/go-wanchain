#!/bin/bash
# set -x
echo ''
echo ''
echo '=========================================='
echo '|  Welcome to Mainnet Validator Deploy   |'
echo ''
echo 'Please Enter your validator Name:'
read YOUR_NODE_NAME

echo -e "\033[41;30m !!!!!! WARNING Please Remember Your Password !!!!!!!! \033[0m"
echo -e "\033[41;30m !!!!!!Otherwise You will lose all your assets!!!!!!!! \033[0m"
echo 'Enter your password of validator account:'
read -s PASSWD
echo 'Confirm your password of validator account:'
read -s PASSWD2
echo ''

echo ''
read -p "Do you want save your password to disk for auto restart? (N/y): " savepasswd
read -p "Do you want to upload the host information (CPU, Memory, Disk, etc.) to the Wanchain log server? (N/y): " allowMonitor


DOCKERIMG=wanchain/client-go:3.0.2
GCMODE='full'
if [ "$GCMODEENV" = "archive" ]; then
    GCMODE='archive'
fi
if [ ${PASSWD} != ${PASSWD2} ]
then
    echo 'Passwords mismatched'
    exit
fi

sudo wget -qO- https://get.docker.com/ | sh
sudo usermod -aG docker ${USER}
if [ $? -ne 0 ]; then
    echo "sudo usermod -aG docker ${USER} failed"
    exit 1
fi

sudo service docker start
if [ $? -ne 0 ]; then
    echo "service docker start failed"
    exit 1
fi

sudo docker pull ${DOCKERIMG}
if [ $? -ne 0 ]; then
    echo "docker pull failed"
    exit 1
fi

# check if there is a snapshot
if [ -f $HOME/gwandata.tgz ]; then
    allowSnapshot=0
    read -p "A snapshot file was found in your home directory. Would you like to use it? (N/y): " allowSnapshot
    if [ "$allowSnapshot" == "Y" ] || [ "$allowSnapshot" == "y" ]; then
        sudo apt install -y jq > /dev/null
        SUMURL="https://raw.githubusercontent.com/wanchain/go-wanchain/refs/heads/develop/loadScript/snapshotMainnetChecksum.json"
        OUTPUT_FILE="/tmp/config.json"
        curl -s -o "$OUTPUT_FILE" "$SUMURL"
        eChecksum=$(jq -r '.checksum' "$OUTPUT_FILE")

        echo "Calculating the snapshot checksum, please wait about 10 minutes"
        checksum=$(sha256sum $HOME/gwandata.tgz | awk '{print $1}')
        if [ $checksum != $eChecksum ]; then
            echo "Checksum mismatched"
            exit -1
        else
            echo "Checksum matched, please wait about 15 minutes to unzip"
        fi
        
        rm -rf $HOME/gwandatatmp
        mkdir -p $HOME/gwandatatmp
        tar zxf ~/gwandata.tgz  -C $HOME/gwandatatmp/
        sudo rm -rf $HOME/.wanchain/gwan
        sudo mkdir -p $HOME/.wanchain
        sudo mv $HOME/gwandatatmp/gwan $HOME/.wanchain/
        sudo rm -rf $HOME/gwandatatmp
    fi
    sudo rm -rf $HOME/gwandata.tgz
fi


getAddr=$(sudo docker run --rm --privileged -v ~/.wanchain:/root/.wanchain ${DOCKERIMG} /bin/gwan console --exec "personal.newAccount('${PASSWD}')")

ADDR=$getAddr

echo $ADDR

getPK=$(sudo docker run --rm --privileged -v ~/.wanchain:/root/.wanchain ${DOCKERIMG} /bin/gwan console --exec "personal.showPublicKey(${ADDR},'${PASSWD}')")
PK=$getPK

echo $PK

echo ${PASSWD} | sudo tee ~/.wanchain/pw.txt > /dev/null
if [ $? -ne 0 ]; then
    echo "write pw.txt failed"
    exit 1
fi

addrNew=`echo ${ADDR} | sed 's/.\(.*\)/\1/' | sed 's/\(.*\)./\1/'`

sudo touch ~/.wanchain/startGwan.sh
sudo chmod 666 ~/.wanchain/startGwan.sh
sudo echo '#!/bin/bash'  > ~/.wanchain/startGwan.sh
sudo echo ''  >> ~/.wanchain/startGwan.sh
if [ "$allowMonitor" == "Y" ] || [ "$allowMonitor" == "y" ]; then
    sudo echo "/bin/monitor.sh 1514 &" >> ~/.wanchain/startGwan.sh
fi
sudo echo "/bin/gwan --gcmode=${GCMODE} --miner.etherbase ${addrNew} --unlock ${addrNew} --password /root/.wanchain/pw.txt --mine --miner.threads=1 --ethstats ${YOUR_NODE_NAME}:wanchainmainnetvalidator@wanstats.io" >> ~/.wanchain/startGwan.sh
sudo chmod 755 ~/.wanchain/startGwan.sh

IPCFILE="$HOME/.wanchain/gwan.ipc"
sudo rm -f $IPCFILE

sudo docker run --privileged -d --log-opt max-size=100m --log-opt max-file=3 --name gwan -p 17717:17717 -p 17717:17717/udp -v ~/.wanchain:/root/.wanchain ${DOCKERIMG} /root/.wanchain/startGwan.sh

if [ $? -ne 0 ]; then
    echo "docker run failed"
    exit 1
fi

echo 'Please wait a few seconds...'

sleep 30

if [ "$savepasswd" == "Y" ] || [ "$savepasswd" == "y" ]; then
    echo ''
else
    while true
    do
        sudo ls -l $IPCFILE > /dev/null 2>&1
        Ret=$?
        if [ $Ret -eq 0 ]; then
            cur=`date '+%s'`
            ft=`sudo stat -c %Y $IPCFILE`
            if [ $cur -gt $((ft + 6)) ]; then
                break
            fi
        fi
        echo -n '.'
        sleep 1
    done
    sudo rm ~/.wanchain/pw.txt
    if [ $? -ne 0 ]; then
        echo "rm pw.txt failed"
        exit 1
    fi
fi

KEYSTOREFILE=$(sudo ls ~/.wanchain/keystore/)

KEYSTORE=$(sudo cat ~/.wanchain/keystore/${KEYSTOREFILE})

echo ''
echo ''
echo -e "\033[41;30m !!!!!!!!!!!!!!! Important !!!!!!!!!!!!!!! \033[0m"
echo '=================================================='
echo '      Please Backup Your Validator Address'
echo '     ' ${ADDR}
echo '=================================================='
echo '      Please Backup Your Validator Public Key'
echo ${PK}
echo '=================================================='
echo '      Please Backup Your Keystore JSON String'
echo ''
echo ${KEYSTORE}
echo ''
echo '=================================================='
echo ''

if [ $(ps -ef | grep -v "grep\b" | grep -c "/bin/gwan\b") -gt 0 ];
then 
    if [ "$savepasswd" == "Y" ] || [ "$savepasswd" == "y" ]; then
        sudo docker container update --restart=always gwan
    fi
    echo "Validator Start Success";
else
    echo "Validator Start Failed";
    echo "Please use command 'sudo docker logs gwan' to check reason." 
fi
