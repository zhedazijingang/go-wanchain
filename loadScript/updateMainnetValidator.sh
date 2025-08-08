#!/bin/bash
# set -x
DOCKERIMG=wanchain/client-go:3.0.2

echo ''
echo ''
echo ''
echo ''
echo '=========================================='
echo '|  Welcome to Mainnet Validator Update   |'
echo ''
echo 'If you have deployed your validator with deployValidator.sh, you can update with this script'
echo 'Please make sure that only one gwan docker is running on the current machine.'
echo 'Otherwise, please update the gwan version manually.'
echo 'gwan binary URL: https://github.com/wanchain/go-wanchain/releases'
echo 'gwan docker image: ' ${DOCKERIMG}
echo ''
echo ''

freeDisk=$(df -k $HOME | sed -n 2p | awk '{print $4}')
if [ $freeDisk -lt 20000000 ] ; then
	echo " Your disk free storage is not enough(less than 20G), please check and try again"
	exit -1
fi

echo 'Please Enter your validator Name:'
read YOUR_NODE_NAME
echo 'Please Enter your validator Address'
read addrNew
echo 'Please Enter your password of Validator account:'
read -s PASSWD
read -p "Do you want save your password to disk for auto restart? (N/y): " savepasswd
read -p "Do you want to upload the host information (CPU, Memory, Disk, etc.) to the Wanchain log server? (N/y): " allowMonitor
echo ''
echo ''
echo ''
echo ''
echo ''

eBlockNumber=0
localBlockNumber=0
localBlockNumberOk=1
DOCKERID=$(sudo docker ps|grep gwan|awk '{print $1}')
GCMODE='full'
if [ "$GCMODEENV" = "archive" ]; then
    GCMODE='archive'
fi

sudo docker pull ${DOCKERIMG}
if [ $? -ne 0 ]; then
    echo "Docker Pull failed. Please verify your Access of docker command."
    echo "You can add yourself into docker group by this command, and re-login:"
    echo "sudo usermod -aG docker ${USER}"
    exit 1
else
    echo "docker pull succeed"
fi

# check if there is a snapshot
if [ -f $HOME/gwandata.tgz ]; then
    allowSnapshot=0
    read -p "A snapshot file was found in your home directory. Would you like to use it? (N/y): " allowSnapshot
    if [ "$allowSnapshot" == "Y" ] || [ "$allowSnapshot" == "y" ]; then
        # check if there is 90G free disk space. for tar 
        freeDisk=$(df -k $HOME | sed -n 2p | awk '{print $4}')
        if [ $freeDisk -lt 90000000 ] ; then
            read -p  "Your disk free storage is not enough(less than 90G), would you like to remove gwan chain data? (N/y): " allowDelete
            if [ "$allowDelete" == "Y" ] || [ "$allowDelete" == "y" ]; then
                echo ""
            else
                exit -1
            fi
        fi

        sudo apt install -y jq > /dev/null
        SUMURL="https://raw.githubusercontent.com/wanchain/go-wanchain/refs/heads/develop/loadScript/snapshotMainnetChecksum.json"
        OUTPUT_FILE="/tmp/config.json"
        curl -s -o "$OUTPUT_FILE" "$SUMURL"
        eChecksum=$(jq -r '.checksum' "$OUTPUT_FILE")
        eBlockNumber=$(jq -r '.blockNumber' "$OUTPUT_FILE")
        echo "Calculating the snapshot checksum, please wait about 10 minutes"
        checksum=$(sha256sum $HOME/gwandata.tgz | awk '{print $1}')
        if [ $checksum != $eChecksum ]; then
            echo "Checksum mismatched"
            exit -1
        else
            echo "Checksum matched, please wait about 15 minutes to unzip"
        fi

        # check if there is 90G free disk space. for tar 
        if [ "$allowDelete" == "Y" ] || [ "$allowDelete" == "y" ]; then
            sudo docker stop gwan >/dev/null 2>&1
            localBlockNumber=$(sudo docker run --rm --privileged -v ~/.wanchain:/root/.wanchain wanchain/client-go:3.0.2 /bin/gwan  console --exec "eth.blockNumber" 2>/dev/null)
            localBlockNumberOk=$?
            echo $localBlockNumberOk $localBlockNumber
            sudo rm -rf $HOME/.wanchain/gwan/chaindata
        fi

        rm -rf $HOME/gwandatatmp
        mkdir -p $HOME/gwandatatmp
        tar zxf ~/gwandata.tgz  -C $HOME/gwandatatmp/
    fi
    sudo rm -rf $HOME/gwandata.tgz
fi



sudo docker stop ${DOCKERID} >/dev/null 2>&1

sudo docker rm ${DOCKERID} >/dev/null 2>&1

sudo docker stop gwan >/dev/null 2>&1

sudo docker rm gwan >/dev/null 2>&1

# check if there is a snapshot
if [ -d $HOME/gwandatatmp/gwan/avgretdb ]; then
    # check if there is the .wanchain/gwan
    sudo mkdir -p $HOME/.wanchain
    if [ -d $HOME/.wanchain/gwan/avgretdb ]; then
        if (($localBlockNumberOk != 0)); then
	        localBlockNumber=$(sudo docker run --rm --privileged -v ~/.wanchain:/root/.wanchain wanchain/client-go:3.0.2 /bin/gwan  console --exec "eth.blockNumber" 2>/dev/null)
	        localBlockNumberOk=$?
	        echo $localBlockNumberOk $localBlockNumber
        fi
        if (( $localBlockNumberOk == 0 && $localBlockNumber > $eBlockNumber )); then
            sudo cp $HOME/.wanchain/gwan/avgretdb/* $HOME/gwandatatmp/gwan/avgretdb
            sudo cp $HOME/.wanchain/gwan/eplocaldb/* $HOME/gwandatatmp/gwan/eplocaldb
            sudo cp $HOME/.wanchain/gwan/rblocaldb/* $HOME/gwandatatmp/gwan/rblocaldb
            sudo cp $HOME/.wanchain/gwan/pos/* $HOME/gwandatatmp/gwan/pos
            sudo cp $HOME/.wanchain/gwan/incentive/* $HOME/gwandatatmp/gwan/incentive
            sudo cp $HOME/.wanchain/gwan/nodekey $HOME/gwandatatmp/gwan
        fi
    fi
    sudo rm -rf $HOME/.wanchain/gwan
    sudo mv $HOME/gwandatatmp/gwan $HOME/.wanchain/
    sudo rm -rf $HOME/gwandatatmp
fi

waddrCount=$(sudo docker run --privileged --name gwan -v ${HOME}/.wanchain:/root/.wanchain ${DOCKERIMG} /bin/gwan account  pubkeys ${addrNew} ${PASSWD} | grep waddress | wc -l)
sudo docker rm gwan >/dev/null 2>&1
echo waddrCount $waddrCount
if [ $waddrCount -ne 1 ]; then
    echo 'Invalid password, please try again'
    exit 1
fi

echo ${PASSWD} | sudo tee ~/.wanchain/pw.txt > /dev/null
if [ $? -ne 0 ]; then
    echo "Write pw.txt failed"
    exit 1
fi

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

echo ''
echo ''
echo ''
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
