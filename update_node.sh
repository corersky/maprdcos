#!/bin/bash

. ./cluster.conf

MEUSER=$(whoami)

if [ "$MEUSER" != "$IUSER" ]; then
    echo "This script needs to be un as $IUSER. Current User: $MEUSER"
    exit 1
fi

if [ ! -f "$PRVKEY" ]; then
    echo "Private does not exist at $PRVKEY"
    echo "Perhaps you need to move the private key to this node?"
    exit 1
fi

NODE_HOST=$1

OUT=$(echo $CLDBS|grep $NODE_HOST)

if [ "$OUT" != "" ]; then
    MID="shared/mapr/cldbs/cldb${NODE_HOST}"
    MFILE="./cldb_marathon/mapr_cldb_${NODE_HOST}.marathon"
    NTYPE="CLDB"
else
    MID="shared/mapr/stdnodes/std${NODE_HOST}"
    MFILE="./stdnode_marathon/mapr_std_${NODE_HOST}.marathon"
    NTYPE="STD"
fi


if [ ! -f "$MFILE" ]; then
    echo "That doesn't appear to be a valid CLDB or STD Node"
    exit 1
fi

echo "You wish to update $NODE_HOST mapr running at $MID, using $MFILE"
echo ""
echo "This is a $NTYPE node"
echo ""

ORIG_FILE=$(cat $MFILE)
echo "$ORIG_FILE"
CUR_FILE_IMG=$(echo "$ORIG_FILE"|grep -P -o "\"image\"\: ?\"[^\"]+\""|cut -f2,3,4,5 -d":"|sed "s/\"//g"|sed "s/ //g")


MARATHON_DEP="http://$MARATHON_HOST/v2/deployments"

CUR=$(curl -s -X GET ${MARATHON_SUBMIT}/$MID -H "Content-type: application/json")

CUR_IMG=$(echo $CUR|grep -P -o "\"image\"\:\"[^\"]+\""|cut -f2,3,4,5 -d":"|sed "s/\"//g"|sed "s/ //g")


echo "Current Running Image: $CUR_IMG"
echo "Image listed in file (Should match): $CUR_FILE_IMG"

echo "Options to replace image with:"
echo ""
sudo docker images --format "table {{.Repository}}:{{.Tag}}"|grep "maprdocker:"
echo ""
read -e -p "Enter Image name you wish to use: " NEW_IMG
echo ""
CHK=$(sudo docker images --format "table {{.Repository}}:{{.Tag}}"|grep "maprdocker:"|grep "$NEW_IMG")
if [ "$CHK" == "" ]; then
    echo "I'm sorry that image isn't found in the list Please try again"
    exit 1
fi

echo "You wish to replace $CUR_IMG with $NEW_IMG"
echo ""
read -e -p "Are you sure you wish to stop the current instance, update the app, and restart? " -i "N" DOIT

if [ "$DOIT" == "Y" ]; then
    OUT=$(curl -s -H "Content-type: application/json" -X PUT ${MARATHON_SUBMIT}/$MID -d'{"instances":0}')
    DEP_ID=$(echo $OUT|grep -P -o "deploymentId\":\"[^\"]+\""|cut -f2 -d":"|sed "s/\"//g")

    DEPLOY=$(curl -s -H "Content-type: application/json" -X GET ${MARATHON_DEP}|grep "$DEP_ID")
    while [ "$DEPLOY" != "" ]; do
        echo "Waiting in a loop for current instance to stop - Waiting 2 seconds"
        sleep 2
        DEPLOY=$(curl -s -H "Content-type: application/json" -X GET ${MARATHON_DEP}|grep "$DEP_ID")
    done
    echo ""
    echo "$DEP_ID has finished moving on..."
    echo ""
    echo "Updating File:"
    sed -i "s@$CUR_IMG@$NEW_IMG@g" $MFILE
    echo "Starting Instance:"
    curl -s -H "Content-type: application/json" -X PUT ${MARATHON_SUBMIT}/$MID -d @$MFILE
    echo ""
else
    echo "Not updating"
    exit 1
fi
