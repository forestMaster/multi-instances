#!/bin/bash
# Create a new instance
RACINE="/var/www/collec2App/"
RACINESED="\/var\/www\/collec2App\/"
CURRENT="${PWD}"
REPOSITORY="/var/local/collec-science/multi-instances"
INSTANCES="$REPOSITORY/instances.csv"

# Variables of environment
DATABASE=collec_$INSTANCE
LOGIN=collec
PASSWORD=collecPassword
URL=$INSTANCE.collec-science.inrae.fr

# gestion des parametres
OK=0
while [ $OK == 0 ]
do
    read -p "Name of the instance to be created: " INSTANCE
    read -p "Identification mode (CAS, CAS-BDD, BDD, HEADER) : " IDENTMODE
    read -p "First admin login: " LOGINADMIN
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

echo "Create the instance $INSTANCE"
ENV="$RACINE/env"
FOLDER="$RACINE$INSTANCE"
FOLDERSED="$RACINESED$INSTANCE"
mkdir "$FOLDER"
chmod g+r "$FOLDER"
cd "$FOLDER"
mkdir temp
chmod g+w temp

# Create the keys of encryption
openssl genpkey -algorithm rsa -out id_collec -pkeyopt rsa_keygen_bits:2048
openssl rsa -in id_collec -pubout -out id_collec.pub
chmod 640 id_collec

# Update parameters of environment
cp $ENV .env

sed -i "s/https:\/\/collec.mysociety.com/https:\/\/$URL/" .env
sed -i "s/database.default.database = collec/database.default.database = $DATABASE/" .env
sed -i "s/IdentificationConfig.identificationMode = BDD/IdentificationConfig.identificationMode = $IDENTMODE/" .env
sed -i "s/disableTotpToAdmin=1/disableTotpToAdmin=0/" .env
sed -i "s/TEMP = /\#TEMP = /" .env
sed -i "s/\#TEMP for multinstance/TEMP = \"$FOLDERSED\/temp\/\"/" .env
sed -i "s/id_collec/$FOLDERSED\/id_collec/" .env
sed -i "s/database.default.password = collecPassword/database.default.password = $PASSWORD/" .env

# Update rights in directories
chgrp -R www-data $FOLDER
chmod 770 $FOLDER/temp

# Generate Apache virtual host
if [ $MODE == "HEADER" ] ;
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
a2ensite collec2-$INSTANCE.conf

# add directory site to manage rights (only one time)
if [ ! -e /etc/apache2/sites-enabled/collecdirectory.conf ]; then
    cp $REPOSITORY/collecdirectory.conf /etc/apache2/sites-available/
    a2ensite collecdirectory.conf
fi

echo "Create the database"
DBSCRIPT="$REPOSITORY/libs/createDatabase.sql"
sed -i "s/dbcollec/$DATABASE/" $DBSCRIPT
su postgres -c "psql -f $DBSCRIPT"
sed -i "s/$DATABASE/dbcollec/" $DBSCRIPT

# add the first account with admin rights

SQL="insert into gacl.acllogin (login,logindetail) values ('$LOGINADMIN','administrator')"
ADDRESS=postgresql://$LOGIN:$PASSWORD@localhost/$DATABASE
psql $ADDRESS -c "$SQL"
SQL="insert into gacl.acllogingroup (acllogin_id, aclgroup_id) values (2,1)"
psql $ADDRESS -c "$SQL"

if [ $IDENTMODE == "HEADER" ]
then
    SQL="insert into gacl.logingestion (login, actif) values ('$LOGINADMIN', 1)"
    psql $ADDRESS -c "$SQL"
fi

# update parameters in dbparam
SQL="update col.dbparam set dbparam_value = '$INSTANCE' where dbparam_name = 'APPLI_code';"
psql $ADDRESS -c "$SQL"
SQL="update col.dbparam set dbparam_value = 'Collec-Science - $INSTANCE' where dbparam_name = 'otp_issuer' or dbparam_name = 'APPLI_title';"
psql $ADDRESS -c "$SQL"

# Add the instance in the instances.csv file
if [ ! -e $INSTANCES ]; then
    cp $DIRECTORY/instances-dist.csv $DIRECTORY/instances.csv
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

