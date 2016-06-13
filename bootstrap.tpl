#!/usr/bin/env bash
OS=$(uname -s)

if [ "$OS" == "SunOS" ]; then
    echo BAL1
    if [ -f /root/.uscript.lock ]; then
        echo "we have already ran"
        exit 0
    else
        date > /root/.uscript.lock
    fi
    # Grab serial number from zonename
    SERIAL=`zonename`
elif [ -d /var/lib/cloud/instance ]; then
    SERIAL=`basename $(ls /var/lib/cloud/instances)`
else
    # Grab serial number from dmidecode
    SERIAL=`dmidecode |grep -i serial |awk '{print $NF}' |head -n 1`
fi

if [ "${real_customer}" == "none" ]; then
REAL_CUSTOMER=${customer}
else
REAL_CUSTOMER=${real_customer}
fi

if [ ! -f /etc/ict.profile ]; then
    cat >> /etc/ict.profile << EOP
CHASSIS=EC2_VIRTUAL
CONFTAG=${conftag}
PACKAGE_SIZE=${package_size}
LOCATION=ec2
OWNER=ictops
CUSTOMER=$${REAL_CUSTOMER}
SERIAL=$${SERIAL}
CREATOR=terraform
NETWORK=PROD
EOP
fi

export PATH=$PATH:/usr/local/bin/:/opt/local/bin:/sbin:/usr/sbin
. /etc/ict.profile

mkdir -p /opt/emeril
mkdir -p /etc/products

if [ "$OS" == "SunOS" ]; then
    IP=$(/sbin/ifconfig net0 | awk '/inet/ {print $2}')
    HN=$(echo $IP |tr "." "-"|awk '{print "prd-"$1}')
    DOMAIN=nodes.ec2.dmtio.net
    echo $DOMAIN > /etc/defaultdomain
    echo "$IP $HN.$DOMAIN $HN" >> /etc/hosts
    hostname $HN
    echo $HN > /etc/nodename

    pkgin -y in pdsh

else
    IP=$(/sbin/ifconfig eth0 | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')
    HN=$(echo $IP |tr "." "-"|awk '{print "prd-"$1}')
    DOMAIN=nodes.ec2.dmtio.net

    if [ $HN != $(hostname -s) ]; then
        echo "$HN.$DOMAIN" > /etc/hostname
        hostname $HN
        echo "$IP $HN.$DOMAIN $HN" >> /etc/hosts
    fi

    cd /tmp
    curl -k -O https://${artifacts_credentials}@${artifacts_endpoint}/pdsh/pdsh_2.26_amd64.deb
    dpkg -i pdsh_2.26_amd64.deb

fi

which emeril
if [ $? == 0 ]; then
    echo "we already have emeril, so assume we already ran"
    exit 0
fi

REPO=repo.ec2.dmtio.net

if [ "$OS" == "SunOS" ]; then
    export PATH=/opt/local/bin:/opt/local/sbin:$PATH

    RET=1
    until [ $${RET} -eq 0 ]; do
        host $REPO
        RET=$?
        if [ $RET -ne 0 ]; then
            sleep 10
        fi
    done

else
    apt-get update
    apt-get install -y curl
fi

cd /tmp
curl -s -L -O http://$REPO/emeril/master/emeril.tar.gz
cd /opt/emeril
tar -xf /tmp/emeril.tar.gz
if [ -f  /opt/emeril/scripts/install.sh ]; then
    /opt/emeril/scripts/install.sh
fi

cd /tmp
ASSETS_URL="assets.services.ec2.dmtio.net"
[ -z "$(dig +noall +answer +nocomments $ASSETS_URL)" ] && ASSETS_URL='assets.services.dmtio.net'
curl -O http://$ASSETS_URL/emeril-assets/${conftag}.tgz
cd /opt/emeril
tar -xzf /tmp/${conftag}.tgz

rm /tmp/${conftag}.tgz

chown root /opt/emeril/cookbooks
chmod 0700 /opt/emeril/cookbooks

chown root /opt/emeril/products
chmod 0700 /opt/emeril/products

if [ "${disk_type}" == "ext4-small" ]; then
# Setup disks on node
umount /mnt
mkfs.ext4 -t ext4 -T small /dev/xvdb
mount /dev/xvdb /mnt
fi

cat <<EOF >> /root/bootstrap.sh
#!/usr/bin/env bash
/usr/local/bin/product-install base prod

/usr/local/bin/emeril base
/usr/local/sbin/emeril-assets-update
/usr/local/bin/emeril base

# Install barge products in order
EOF

IFS=',' read -r -a array <<< "${products}"

for element in "$${array[@]}"
do
  IFS=':' read -r -a array2 <<< "$$element"
  cat <<EOF >> /root/bootstrap.sh
/usr/local/bin/product-install $${array2[0]} $${array2[1]}
/usr/local/bin/emeril $${array2[0]}

EOF
done

echo "bash /root/bootstrap.sh > /var/log/bootstrap.log 2>&1" | at now
