#!/bin/bash
# Création d'une nouvelle instance en s'appuyant sur la configuration présente dans le dossier migrate25
RACINE="/var/www/collec2App/"
RACINESED="\/var\/www\/collec2App\/"
CURRENT="${PWD}"
VERSION="25.0"

# gestion des parametres
OK=0
while [ $OK == 0 ]
do
	read -p "Nom de l'instance à créer : " INSTANCE
	read -p "Mode d'identification (CAS, CAS-BDD, BDD, HEADER) : " IDENTMODE
	read -p "Premier login d'administration : " LOGINADMIN
	echo "Nom de l'instance : "$INSTANCE
	echo "Mode d'identification : "$IDENTMODE
	echo "Login d'administration : "$LOGINADMIN
	read -p "Créer l'instance [o/n/q] ? " REPONSE
	if  [ $REPONSE == 'o' ] 
	then
		break;
	elif [ $REPONSE == 'q' ] 
	then
		exit 0;
	fi
done

echo "Création de l'instance $INSTANCE"
ENV="$RACINE/env"
FOLDER="$RACINE$INSTANCE"
FOLDERSED="$RACINESED$INSTANCE"
mkdir "$FOLDER"
chmod g+r "$FOLDER"
cd "$FOLDER"
mkdir temp
chmod g+w temp

# Création des clés de chiffrement
openssl genpkey -algorithm rsa -out id_collec -pkeyopt rsa_keygen_bits:2048
openssl rsa -in id_collec -pubout -out id_collec.pub
chmod 640 id_collec

# Mise à niveau des parametres d'environnement
cp $ENV .env
DATABASE=collec_$INSTANCE
LOGIN=collec
PASSWORD=XXXXXXX
URL=$INSTANCE.collec-science.inrae.fr
sed -i "s/https:\/\/collec.mysociety.com/https:\/\/$URL/" .env
sed -i "s/database.default.database = collec/database.default.database = $DATABASE/" .env
#sed -i "s/database.default.username = collec/database.default.username = $LOGIN/" .env
sed -i "s/IdentificationConfig.identificationMode = CAS/IdentificationConfig.identificationMode = $IDENTMODE/" .env
sed -i "s/disableTotpToAdmin=1/disableTotpToAdmin=0/" .env
sed -i "s/TEMP = /\#TEMP = /" .env
sed -i "s/\#TEMP for multinstance/TEMP = \"$FOLDERSED\/temp\/\"/" .env
sed -i "s/id_collec/$FOLDERSED\/id_collec/" .env
sed -i "s/database.default.password = collecPassword/database.default.password = $PASSWORD/" .env

# Mise à niveau des droits dans les dossiers
chgrp -R www-data $FOLDER
chmod 770 $FOLDER/temp

# Traitement du virtual host apache
if [ $MODE == "HEADER" ] ;
then
	VHOST="/var/local/collec-science/migrate25/collec2-header.conf"
else
	VHOST="/var/local/collec-science/migrate25/collec2.conf"
fi
VHOSTNAME="/etc/apache2/sites-available/collec2-$INSTANCE.conf"
cp $VHOST $VHOSTNAME
sed -i "s/envPath \/var\/www\/collec2App\/collec-science/envPath \/var\/www\/collec2App\/$INSTANCE/" $VHOSTNAME
sed -i "s/collec.mysociety.com/$URL/" $VHOSTNAME
sed -i "s/collec-access.log/$INSTANCE-access.log/" $VHOSTNAME
sed -i "s/collec-error.log/$INSTANCE-error.log/" $VHOSTNAME
a2ensite collec2-$INSTANCE.conf

echo "Création de la base de données"
DBSCRIPT="/var/local/collec-science/migrate25/createDatabase.sql"
sed -i "s/dbcollec/$DATABASE/" $DBSCRIPT
su postgres -c "psql -f $DBSCRIPT"
sed -i "s/$DATABASE/dbcollec/" $DBSCRIPT

# Ajout du premier compte d'administration

SQL="insert into gacl.acllogin (login,logindetail) values ('$LOGINADMIN','administrateur')"
ADDRESS=postgresql://$LOGIN:$PASSWORD@localhost/$DATABASE
psql $ADDRESS -c "$SQL"
SQL="insert into gacl.acllogingroup (acllogin_id, aclgroup_id) values (2,1)"
psql $ADDRESS -c "$SQL"

if [ $IDENTMODE == "HEADER" ] 
then
	SQL="insert into gacl.logingestion (login, actif) values ('$LOGINADMIN', 1)"
	psql $ADDRESS -c "$SQL"
fi

# Mise à niveau des parametres dans dbparam
SQL="update col.dbparam set dbparam_value = '$INSTANCE' where dbparam_name = 'APPLI_code';"
psql $ADDRESS -c "$SQL"
SQL="update col.dbparam set dbparam_value = 'Collec-Science - $INSTANCE' where dbparam_name = 'otp_issuer' or dbparam_name = 'APPLI_title';"
psql $ADDRESS -c "$SQL"

# Ajout de l'instance dans le fichier instances.csv
INSTANCES="/var/local/collec-science/instances.csv"
echo "$INSTANCE;$VERSION;localhost;collec_$INSTANCE;collec;adm1n0verall;$VERSION;$IDENTMODE;$URL;" >> $INSTANCES

echo "============="
echo "Fin de création de l'instance"
echo "Si vous avez activé une identification CAS ou HEADER, vous devrez réaliser les demandes d'accès correspondantes"
echo "Vérifiez si vous avez eu des messages d'erreur dans les scripts qui ont été exécutés"
echo "Vérifiez également le fichier $VHOSTNAME, pour le paramétrage Apache"
echo "et le fichier $FOLDER/.env, qui contient les paramètres spécifiques de l'instance"
echo ""
echo "Une fois que tout est ok, vous pouvez activer l'instance avec la commande :"
echo "systemctl reload apache2"
echo "Enfin, vérifiez le contenu du fichier $INSTANCES, puis enregistrez-le dans le dépôt (git add *, git status, git commit -m 'création de l'instance $INSTANCE', git push" 
echo "============="
cd $CURRENT

