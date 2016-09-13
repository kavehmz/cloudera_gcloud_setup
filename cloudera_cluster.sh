#!/bin/bash
echo "Checking gcloud command and if it is setup correcting by issuing 'gcloud info'"
gcloud info >/dev/null || { echo "You need to install Google Cloud SDK and set it up first"; exit 1; }

GCLOUD_ZONE='europe-west1-b'
NODES=3

echo "Creating the manager in zone [$GCLOUD_ZONE]"
NODENAME=cloudera-manager
echo $GCLOUD_ZONE-$NODENAME
gcloud compute instances create "$GCLOUD_ZONE-$NODENAME" \
	--zone "$GCLOUD_ZONE" --machine-type "n1-highmem-2" \
	--image "/ubuntu-os-cloud/ubuntu-1404-trusty-v20160809a" \
	--boot-disk-size "200"
MANAGERIP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-manager --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
LOCALMANAGERIP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-manager --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)

echo "Creating nodes in zone [$GCLOUD_ZONE]"
for i in $(seq 1 $NODES)
do
	NODENAME=cloudera-node$i
	echo $GCLOUD_ZONE-$NODENAME
	gcloud compute instances create "$GCLOUD_ZONE-$NODENAME" \
		--zone "$GCLOUD_ZONE" --machine-type "n1-highmem-2" \
		--image "/ubuntu-os-cloud/ubuntu-1404-trusty-v20160809a" \
		--boot-disk-size "200"
	export NODEIP$i=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node$i --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
	export LOCALNODEIP$i=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node$i --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)
done

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
ssh kaveh@$MANAGERIP 'sudo sudo -su postgres psql -c "CREATE database reports"'
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

echo "Set authorized_keys/swappiness"
for i in $(seq 1 $NODES)
do
	NAME=NODEIP$i;
	IP="${!NAME}";
	echo $IP;
	ssh kaveh@$IP "echo '$PUBKEY' >> ~/.ssh/authorized_keys"
	ssh kaveh@$IP "sudo bash -c 'echo 10  > /proc/sys/vm/swappiness'"
	ssh kaveh@$IP "sudo bash -c 'echo vm.swappiness=10 >> /etc/sysctl.conf'"
done

for i in $(seq 1 $NODES)
do
	NAME=NODEIP$i
	LNAME=LOCAL$NAME
	LOCALIP="${!LNAME}"
	IP="${!NAME}"
	echo "$IP/$LOCALIP"

	RDNS=$(ssh kaveh@$MANAGERIP "host $LOCALIP" |perl -e '$a=<>; $a =~ /pointer (.*)\.$/;print $1,"\n"')
	echo $RDNS

	ssh -i ~/.ssh/cloudera kaveh@$IP "echo '$RDNS' > /tmp/hostname; sudo cp /tmp/hostname /etc/hostname"
	ssh -i ~/.ssh/cloudera kaveh@$IP "sudo hostname '$RDNS'"
done

echo "Enabling Zram to give the servers a bit more memory"
ssh kaveh@$MANAGERIP 'sudo apt-get install -y zram-config'
for i in $(seq 1 $NODES);do NAME=NODEIP$i;IP="${!NAME}";ssh kaveh@$IP 'sudo apt-get install -y zram-config';done

echo "Starting Cloudera Manager Server"
ssh kaveh@$MANAGERIP 'sudo service cloudera-scm-server start'

echo "Wait for few minutes and then opne NOW OPEN http://$MANAGERIP:7180/"
echo "Use and passwords are: admin/admin"
echo "Add the following IPs as extra nodes"
for i in $(seq 1 $NODES);do NAME=LOCALNODEIP$i;IP="${!NAME}";echo $IP;done

echo "DB set is as [$LOCALMANAGERIP cdadmin/letmein]. DB names are lower case of the service name."

