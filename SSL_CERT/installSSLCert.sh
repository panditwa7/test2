#!/bin/sh 
export WORK_DIR=/etc/BSCS/certificate
export CERT_NAME=$1
export CERT_PASS=$2
export CERT_LOCATION=/deploy/bscs/Cert
DATE=`date +%m-%d-%y`
SERVER_XML=${BSCS_RESOURCE}/wsi/embedded-tomcat-config/server.xml
CERT_KEYSTORE=${WORK_DIR}/BSCS_Keystore_$DATE
SUDO_PASS=$(echo "VG1vOGJpbGUhCg==" | openssl enc -base64 -d)
# Use below command to encode the password
#echo $PASS | openssl enc -base64 -e


if [  -f "$CERT_KEYSTORE" ] ; then
	printf "KeyStore file $CERT_KEYSTORE already exists, deleting it ... \n"
	mv $CERT_KEYSTORE $CERT_KEYSTORE_$DATE
fi 

if [ ! -f $CERT_LOCATION/$CERT_NAME ] ; then
	printf "ERROR: certificate file not found. Cannot continue.\n" 
	exit 1
fi 
 

if [  -z $CERT_PASS ] ; then
	printf "ERROR: CERT_PASS variable not set, Can't continue, exiting ...\n" 
	exit 1
fi

cd /etc/BSCS
echo "Cleaning old backup files"
rm -f *.tar

echo "Taking backup of existing keystore and certificate"
tar -cvf certificate.tar certificate

cd $WORK_DIR 
rm -rf *

cp -p $CERT_LOCATION/$CERT_NAME $WORK_DIR

echo $CERT_NAME
echo $CERT_PASS
echo $CERT_KEYSTORE

CERT_TYPE=pkcs12
STORE_TYPE=JKS
ERROR_LOG=$WORK_DIR/error.log

echo "starting backup of server.xml"

cp -p $SERVER_XML ${SERVER_XML}_$DATE

echo "Start SSL importing certificate "

V_COMMAND=`$JAVA_HOME/bin/keytool -importkeystore -srckeystore $WORK_DIR/$CERT_NAME -srcstoretype $CERT_TYPE -destkeystore $CERT_KEYSTORE  -deststoretype $STORE_TYPE -srcstorepass $CERT_PASS -deststorepass $CERT_PASS -storepass $CERT_PASS`

echo "command line : " $V_COMMAND

echo $v_COMMAND > $ERROR_LOG


LOG_check=`grep 'keytool error:' $ERROR_LOG | wc -l`

if [ $LOG_check -ne 0 ];then
        echo " EXECUTION ERROR"
        exit -1
fi

if [ ! -f $CERT_KEYSTORE ] ; then
        printf "ERROR: certificate file not found. Cannot continue.\n"
        exit 1
fi


chmod 775 $CERT_KEYSTORE

echo "Start Listing SSL certificate "

LIST_COMMAND=`$JAVA_HOME/bin/keytool -list -keystore $CERT_KEYSTORE  -storepass $CERT_PASS` 


echo $LIST_COMMAND > $ERROR_LOG 


echo " Migrating JKS to PKCS12" 

MIGRATION_COMMAND=`$JAVA_HOME/bin/keytool -importkeystore -srckeystore $CERT_KEYSTORE  -destkeystore $CERT_KEYSTORE  -deststoretype pkcs12 -srcstorepass $CERT_PASS  -storepass $CERT_PASS`

echo $MIGRATION_COMMAND



LIST_COMMAND=`$JAVA_HOME/bin/keytool -list -keystore $CERT_KEYSTORE  -storepass $CERT_PASS`

echo $LIST_COMMAND 

echo "get Alias name from server.xml"

export keystorePass=$(grep keystorePass $SERVER_XML | awk -F= '{print $10}'| awk '{print $1}'|sed 's/\"//g')
export keyAlias=$(grep keyAlias $SERVER_XML | awk -F= '{print $11}'| awk '{print $1}'|sed 's/\"//g')
export keyport=$(grep keyAlias $SERVER_XML | awk -F= '{print $2}'| awk '{print $1}'|sed 's/\"//g')
export keystoreFile=$(grep keystoreFile $SERVER_XML | awk -F= '{print $12}'| awk '{print $1}'|sed 's/\"//g')


echo $keystorePass
echo $keyAlias
echo $keystoreFile

if [  -z $keystorePass ] ; then
	printf "ERROR: keystorePass variable not set, Can't continue, exiting ...\n" 
	exit 1
fi
if [  -z $keyAlias ] ; then
	printf "ERROR: keyAlias variable not set, Can't continue, exiting ...\n" 
	exit 1
fi
if [  -z $keystoreFile ] ; then
	printf "ERROR: keystoreFile variable not set, Can't continue, exiting ...\n" 
	exit 1
fi

ALIAS_CHANGE=`$JAVA_HOME/bin/keytool -changealias -alias 1 -destalias $keyAlias -keystore $CERT_KEYSTORE -storepass $CERT_PASS`

echo $ALIAS_CHANGE

LIST_COMMAND=`$JAVA_HOME/bin/keytool -list -keystore $CERT_KEYSTORE  -storepass $CERT_PASS`

echo $LIST_COMMAND 


echo "Certificate import finished..."

echo "Changing password in server.xml "

sed -i "s/$keystorePass/$CERT_PASS/g" $SERVER_XML

echo "Changing KeyStore name in server.xml "

sed -i "s#$keystoreFile#$CERT_KEYSTORE#g" $SERVER_XML

sleep 1

echo "Stopping CMS ..."

for PS in `ps -ef | grep cms | grep -v grep |awk '{print $2}'`
do

#sudo kill -9 $PS
echo $SUDO_PASS | sudo -S kill -9 $PS


done 

sleep 2

echo "CMS restart in progress"
sleep 120
echo "Sleeping for 120 seconds"


CMS_CHECK=`ps -ef | grep cms | grep -v grep | head -n 1 | awk '{print $2}'|wc -l`

echo $CMS_CHECK

if 
[ $CMS_CHECK -ne 0 ];then
        echo " CMS is up "
fi

echo "New Certificate expiry date is :"
echo | openssl s_client -connect $keyAlias:$keyport 2>/dev/null | openssl x509 -noout -dates

exit 0
