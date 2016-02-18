#!/bin/bash

sysdba_password="XXXXX"

sudo groupadd firebird
sudo useradd -d /opt/ -s /bin/false -c "Firebird Database Owner" -g firebird firebird

aptitude install xinetd -y


for  firebird_version in FirebirdCS-2.5.5.26952-0.amd64 FirebirdSS-2.5.5.26952-0.amd64 ; do

cd /opt
wget http://sourceforge.net/projects/firebird/files/firebird-linux-amd64/2.5.5-Release/${firebird_version}.tar.gz/download -O ${firebird_version}.tar.gz
tar xvzf ${firebird_version}.tar.gz
rm ${firebird_version}.tar.gz
cd ${firebird_version}
tar xvzf buildroot.tar.gz
mv opt/firebird/* .
rm -rf manifest.txt install.sh scripts opt buildroot.tar.gz usr doc examples include  de_DE.msg fr_FR.msg README IDPLicense.txt IPLicense.txt WhatsNew #misc
cd ..

export FIREBIRD=/opt/${firebird_version}
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${FIREBIRD}/lib/
export PATH=$PATH:${FIREBIRD}/bin/

gsec <<EOF
modify SYSDBA -pw ${sysdba_password}
quit
EOF

done
