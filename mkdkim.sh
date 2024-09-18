#!/bin/bash

# mkdkim.sh
# Provide a domain and selector and this will create a DKIM key for you
# This particular version creates a 1024bit sha256 RSA key
# Usage: bash mkdkim.sh <domain> <selector>
# $SELECTOR.key and $SELECTOR.pub will be written to /opt/kumomta/etc/dkim/$DOMAIN

DOMAIN=$1
SELECTOR=$2
echo "Proceeding with DOMAIN = $MYDOMAIN and SELECTOR = $MYSELECTOR"

sudo mkdir -p /opt/kumomta/etc/dkim/$DOMAIN
sudo openssl genrsa -f4 -out /opt/kumomta/etc/dkim/$DOMAIN/$SELECTOR.key 1024
sudo openssl rsa -in /opt/kumomta/etc/dkim/$DOMAIN/$SELECTOR.key \
    -outform PEM -pubout -out /opt/kumomta/etc/dkim/$DOMAIN/$SELECTOR.pub
sudo chown kumod:kumod /opt/kumomta/etc/dkim/$DOMAIN -R


# To do bulk, create a file domainlist.txt
# Populate it with format like this:
# <domain> <keyname>
# news.suegemi.com newsletter

#And use this auto build script:
#autobuilddkim.sh as below:

#MYFILE=domainlist.txt
#while read p; do
#     	bash mkdkim.sh $p
#done < $MYFILE

