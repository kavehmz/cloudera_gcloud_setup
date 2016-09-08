#!/bin/bash
echo "Checking gcloud command and if it is setup correcting by issuing 'gcloud info'"
gcloud info >/dev/null || { echo "You need to install Google Cloud SDK and set it up first"; exit 1; }

GCLOUD_ZONE='us-central1-a'

echo "Creating the nodes in zone [$GCLOUD_ZONE]"
for NODENAME in cloudera-manager cloudera-node01 cloudera-node02 cloudera-node03;do echo $GCLOUD_ZONE-$NODENAME;gcloud compute instances create "$GCLOUD_ZONE-$NODENAME" --zone "$GCLOUD_ZONE" --machine-type "n1-highmem-2" --image "/ubuntu-os-cloud/ubuntu-1404-trusty-v20160809a" --boot-disk-size "200";done

echo "Getting public IPs to setup nodes"
MANAGERIP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-manager --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
NODE01IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node01 --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
NODE02IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node02 --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
NODE03IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node03 --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)

echo "Getting private IPs for use cloudera cluster setup"
LOCALMANAGERIP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-manager --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)
LOCALNODE01IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node01 --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)
LOCALNODE02IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node02 --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)
LOCALNODE03IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node03 --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)


[Manager]
echo "Adding cloudera repositories for apt"
ssh kaveh@$MANAGERIP "sudo bash -c '" 'echo "deb [arch=amd64] http://archive.cloudera.com/cm5/ubuntu/trusty/amd64/cm trusty-cm5 contrib" > /etc/apt/sources.list.d/cloud.list'"'"
ssh kaveh@$MANAGERIP "sudo bash -c '" 'echo "deb-src http://archive.cloudera.com/cm5/ubuntu/trusty/amd64/cm trusty-cm5 contrib" >> /etc/apt/sources.list.d/cloud.list'"'"
ssh kaveh@$MANAGERIP 'sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 327574EE02A818DD'
ssh kaveh@$MANAGERIP 'sudo apt-get update'

echo "Installing JDK for first setup"
ssh kaveh@$MANAGERIP 'sudo apt-get install -y oracle-j2sdk1.7'

echo "Installing Cloudera Manager Server Packages"
ssh kaveh@$MANAGERIP 'sudo apt-get install -y cloudera-manager-daemons cloudera-manager-server'

echo "Installing postgresql jdbc driver"
ssh kaveh@$MANAGERIP 'sudo curl "https://jdbc.postgresql.org/download/postgresql-9.4.1209.jre6.jar" -o  /usr/share/java/postgresql-connector-java.jar'

echo "Setup postgresql and add cdadmin"
ssh kaveh@$MANAGERIP 'sudo apt-get install -y postgresql-9.3'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE ROLE cdadmin WITH LOGIN  ENCRYPTED PASSWORD '"'letmein'"' SUPERUSER"'

ssh kaveh@$MANAGERIP  "sudo sed -i '1ihost all cdadmin 0.0.0.0/0 md5' /etc/postgresql/9.3/main/pg_hba.conf"
ssh kaveh@$MANAGERIP  "sudo sed -i '1ihost all cdadmin 127.0.0.1/32 trust' /etc/postgresql/9.3/main/pg_hba.conf"
ssh kaveh@$MANAGERIP  'sudo sed -i -e "s/#listen_addresses.*/listen_addresses = '"'*'"'/"  /etc/postgresql/9.3/main/postgresql.conf'

ssh kaveh@$MANAGERIP 'sudo service postgresql restart'

echo "Importing smaple databases of world"
ssh kaveh@$MANAGERIP "curl 'http://pgfoundry.org/frs/download.php/527/world-1.0.tar.gz' -o /tmp/world-1.0.tar.gz"
ssh kaveh@$MANAGERIP "cd /tmp;tar --gzip -xf world-1.0.tar.gz"
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database sample_world"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql sample_world < /tmp/dbsamples-0.1/world/world.sql'

echo "Importing smaple databases of usda"
ssh kaveh@$MANAGERIP "curl 'http://pgfoundry.org/frs/download.php/555/usda-r18-1.0.tar.gz' -o /tmp/usda-r18-1.0.tar.gz"
ssh kaveh@$MANAGERIP "cd /tmp;tar --gzip -xf usda-r18-1.0.tar.gz"
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database sample_usda"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql sample_usda < /tmp/usda-r18-1.0/usda.sql'


echo "Creating some table to e used during cluster setup later. This are emtpy."
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database hive"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database hue"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database report"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database activities"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database oozie"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database sentry"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database nav_au"'
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database nav_meta"'

echo "Prepare databases by calling /usr/share/cmf/schema/scm_prepare_database.sh"
ssh kaveh@$MANAGERIP 'sudo /usr/share/cmf/schema/scm_prepare_database.sh -u localhost -P 5432 -u cdadmin postgresql cmf cmf letmein'



echo "Generating a key on manager node and distributing it to all nodes. One copy will be at ~/.ssh/cloudera"
ssh kaveh@$MANAGERIP 'ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ""  -b 4096 -C "kaveh"'

rm ~/.ssh/cloudera
ssh kaveh@$MANAGERIP 'cat ~/.ssh/id_rsa' > ~/.ssh/cloudera
chmod 400 ~/.ssh/cloudera

PUBKEY=$(ssh kaveh@$MANAGERIP 'cat ~/.ssh/id_rsa.pub')

for IP in $NODE01IP $NODE02IP $NODE03IP;do echo $IP;ssh kaveh@$IP "echo '$PUBKEY' >> ~/.ssh/authorized_keys";done

for IP in $NODE01IP $NODE02IP $NODE03IP;do echo $IP;ssh kaveh@$IP "sudo bash -c 'echo 10  > /proc/sys/vm/swappiness'";done
for IP in $NODE01IP $NODE02IP $NODE03IP;do echo $IP;ssh kaveh@$IP "sudo bash -c 'echo vm.swappiness=10 >> /etc/sysctl.conf'";done


for NAME in NODE01IP NODE02IP NODE03IP
do
	LNAME=LOCAL$NAME
	LOCALIP="${!LNAME}"
	echo $LOCALIP
	IP="${!NAME}"

	RDNS=$(ssh kaveh@$MANAGERIP "host $LOCALIP" |perl -e '$a=<>; $a =~ /pointer (.*)\.$/;print $1,"\n"')
	echo $RDNS

	ssh -i ~/.ssh/cloudera kaveh@$IP "echo '$RDNS' > /tmp/hostname; sudo cp /tmp/hostname /etc/hostname"
	ssh -i ~/.ssh/cloudera kaveh@$IP "sudo hostname '$RDNS'"
done

echo "Enabling Zram to give the servers a bit more memory"
for IP in $MANAGERIP $NODE01IP $NODE02IP $NODE03IP;do echo $IP;ssh kaveh@$IP 'sudo apt-get install -y zram-config';done

each "Starting Cloudera Manager Server"
ssh kaveh@$MANAGERIP 'sudo service cloudera-scm-server start'

echo "Wait for few minutes and then opne NOW OPEN http://$MANAGERIP:7180/"
echo "Use and passwords are: admin/admin"
echo "Add the following IPs as extra nodes"
for IP in $LOCALNODE01IP $LOCALNODE02IP $LOCALNODE03IP;do echo $IP;done
