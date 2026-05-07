#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "This script must be launched as root/admin."
    echo "Use: sudo ./create.sh"
    exit 1
fi
#if instance fail create do : sudo rm -r /var/www/collec2App/collec-science/instancefailedname and sudo -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS collec_instancefailedname;" DANGEROUS if bad name can erase your other instances
#

# Create a new instance
RACINE="/var/www/collec2App/" #/var/www/collec2App/collec-science/ #where code is 
RACINESED="\/var\/www\/collec2App\/"
CURRENT="${PWD}"
REPOSITORY="/var/local/collec-science/multi-instances" # validate its correct
INSTANCES="$REPOSITORY/instances.csv"

SSL_CERT_FILE="/etc/ssl/certs/collec_ZZZ.crt" #CHANGE
SSL_CERT_KEY_FILE="/etc/ssl/private/collec_ZZZ.key" #CHANGE
SSL_CERT_CHAIN_FILE="/etc/ssl/certs/ZZZ.crt" #CHANGE

# gestion des parametres
OK=0
while [ $OK == 0 ]
do
    read -p "Name of the instance to be created: " INSTANCE
    read -p "Identification mode (CAS, CAS-BDD, BDD, HEADER) : " IDENTMODE
    read -p "First admin login (can't be admin): " LOGINADMIN
    echo "Name of the instance: "$INSTANCE
    echo "Identification mode: "$IDENTMODE
    echo "Administrator login: "$LOGINADMIN
    read -p "Create the instance [y/n/q] ? " REPONSE
    if  [ $REPONSE == 'y' ]
    then
        break;
    elif [ $REPONSE == 'q' ]
    then
        exit 0;
    fi
done

# Variables of environment
DATABASE=collec_$INSTANCE
LOGIN=collec #i think user must exist like non multi script before
PASSWORD=collecPassword #can change but must be linked to login
URL=$INSTANCE.collec-science.inrae.fr # CHANGE

echo "Create the instance $INSTANCE"

echo "Create the database"
DBSCRIPT="$REPOSITORY/libs/createDatabase.sql"
TMPDBSCRIPT="$(mktemp)"

sed -e "s/__DBNAME__/$DATABASE/g" \
    -e "s/__DBUSER__/$LOGIN/g" \
    -e "s/__DBPASS__/$PASSWORD/g" \
    "$DBSCRIPT" > "$TMPDBSCRIPT"

# allow only postgres to read it
setfacl -m u:postgres:r "$TMPDBSCRIPT"
sudo -u postgres psql -v ON_ERROR_STOP=1 -f "$TMPDBSCRIPT"
setfacl -b "$TMPDBSCRIPT" || true
rm "$TMPDBSCRIPT"

ADDRESS="postgresql://$LOGIN:$PASSWORD@localhost/$DATABASE"

# add the first account with admin rights
if [ "$IDENTMODE" == "HEADER" ]
then
    HEADER_SQL="insert into gacl.logingestion (login, actif) values ('$LOGINADMIN', 1);"
else
    HEADER_SQL=""
fi

psql "$ADDRESS" -v ON_ERROR_STOP=1 -1 <<SQL
insert into gacl.acllogin (login,logindetail) values ('$LOGINADMIN','administrator');
insert into gacl.acllogingroup (acllogin_id, aclgroup_id) values (2,1);
$HEADER_SQL
update col.dbparam set dbparam_value = '$INSTANCE' where dbparam_name = 'APPLI_code';
update col.dbparam set dbparam_value = 'Collec-Science - $INSTANCE' where dbparam_name = 'otp_issuer' or dbparam_name = 'APPLI_title';
SQL

echo "Create the folder and files"
ENV="$RACINE/env"
FOLDER="$RACINE$INSTANCE"
FOLDERSED="$RACINESED$INSTANCE"
mkdir "$FOLDER"
chmod g+r "$FOLDER"
cd "$FOLDER"
mkdir temp
chmod g+w temp

# Create the keys of encryption
KEY_BASENAME="id_collec_${INSTANCE}"
PRIVATE_KEY_FILE="${KEY_BASENAME}"
PUBLIC_KEY_FILE="${KEY_BASENAME}.pub"

openssl genpkey -algorithm rsa -out "$PRIVATE_KEY_FILE" -pkeyopt rsa_keygen_bits:2048
openssl rsa -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_KEY_FILE"
chmod 640 "$PRIVATE_KEY_FILE"

# Update parameters of environment
cp $ENV .env
chmod 640 .env

sed -i "s/https:\/\/collec.mysociety.com/https:\/\/$URL/" .env
sed -i "s/database.default.database = collec/database.default.database = $DATABASE/" .env
sed -i "s/IdentificationConfig.identificationMode = BDD/IdentificationConfig.identificationMode = $IDENTMODE/" .env
sed -i "s/disableTotpToAdmin=1/disableTotpToAdmin=0/" .env
sed -i "s/TEMP = /\#TEMP = /" .env
sed -i "s/\#TEMP for multinstance/TEMP = \"$FOLDERSED\/temp\/\"/" .env
sed -i "s/id_collec/$FOLDERSED\/id_collec/" .env
sed -i "s/database.default.password = collecPassword/database.default.password = $PASSWORD/" .env

sed -i "s#\(\${BASE_DIR}/\)id_collec\.pub#\1${KEY_BASENAME}.pub#g" .env
sed -i "s#\(\${BASE_DIR}/\)id_collec#\1${KEY_BASENAME}#g" .env

# Update rights in directories
chgrp -R www-data $FOLDER
chmod 770 $FOLDER/temp

# Generate Apache virtual host
if [ $IDENTMODE == "HEADER" ] ;
then
    VHOST="$REPOSITORY/libs/collec2-header.conf"
else
    VHOST="$REPOSITORY/libs/collec2.conf"
fi
VHOSTNAME="/etc/apache2/sites-available/collec2-$INSTANCE.conf"
cp $VHOST $VHOSTNAME
sed -i "s/envPath \/var\/www\/collec2App\/collec-science/envPath \/var\/www\/collec2App\/$INSTANCE/" $VHOSTNAME
sed -i "s/collec.mysociety.com/$URL/" $VHOSTNAME
sed -i "s/collec-access.log/$INSTANCE-access.log/" $VHOSTNAME
sed -i "s/collec-error.log/$INSTANCE-error.log/" $VHOSTNAME

sed -i \
  -e "s#/etc/ssl/certs/collec_science_inrae_fr_cert\.cer#$SSL_CERT_FILE#g" \
  -e "s#/etc/ssl/certs/cert_collec_science_inrae_fr\.key#$SSL_CERT_KEY_FILE#g" \
  -e "s#/etc/ssl/certs/certificats_chain_sectigo\.cer#$SSL_CERT_CHAIN_FILE#g" \
  "$VHOSTNAME"
  
a2ensite collec2-$INSTANCE.conf

# add directory site to manage rights (only one time)
if [ ! -e /etc/apache2/sites-enabled/collecdirectory.conf ]; then
    cp $REPOSITORY/collecdirectory.conf /etc/apache2/sites-available/
    a2ensite collecdirectory.conf
fi

# Add the instance in the instances.csv file
if [ ! -e $INSTANCES ]; then
    cp $REPOSITORY/instances-dist.csv $REPOSITORY/instances.csv
fi

echo "$INSTANCE;localhost;$DATABASE;$LOGIN;$PASSWORD;" >> $INSTANCES

echo "============="
echo "End of creation of the instance"
echo "If you have activate an identification CAS or HEADER, you will need to make the relevant access requests"
echo "Verify if you had error messages into the executed scripts"
echo "Also check the $VHOSTNAME file for the Apache settings"
echo "and the $FOLDER/.env file, which contains the specific settings of the instance"
echo ""
echo "When all is ok, you can activate the instance with this command:"
echo "systemctl reload apache2"
echo "Then, verify the content of $INSTANCES file."
echo "That's all, folks !"
echo "============="
cd $CURRENT

