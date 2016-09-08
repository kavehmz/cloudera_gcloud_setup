#!/usr/bash
GCLOUD_ZONE='us-central1-a'

NODE01IP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-node01 --zone $GCLOUD_ZONE|grep natIP|cut -d' ' -f 6)
LOCALMANAGERIP=$(gcloud compute instances describe $GCLOUD_ZONE-cloudera-manager --zone $GCLOUD_ZONE|grep networkIP|cut -d' ' -f 4)

ssh kaveh@$NODE01IP 'sudo curl "https://jdbc.postgresql.org/download/postgresql-9.4.1209.jre6.jar" -o  /usr/share/java/postgresql-connector-java.jar'

ssh kaveh@$NODE01IP "sudo sudo -u hdfs sqoop import-all-tables  -m 1  --connect jdbc:postgresql://$LOCALMANAGERIP:5432/sample_world  --username=cdadmin  --password=letmein  --compression-codec=snappy  --as-parquetfile  --warehouse-dir=/user/hive/warehouse  --hive-import  --hive-database sample_world --hive-overwrite"
ssh kaveh@$NODE01IP "sudo sudo -u hdfs sqoop import-all-tables  -m 1  --connect jdbc:postgresql://$LOCALMANAGERIP:5432/sample_usda  --username=cdadmin  --password=letmein  --compression-codec=snappy  --as-parquetfile  --warehouse-dir=/user/hive/warehouse  --hive-import  --hive-database sample_usda --hive-overwrite"
