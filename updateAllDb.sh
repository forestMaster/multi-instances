#!/bin/bash
# Version of 2025-06-12
# updated 2026-01-22
# Generic version
FILENAME=/var/local/collec-science/multi-instances/instances.csv
FOLDERINSTALL="/var/www/collec2App/collec-science"
SQL="select dbversion_number from col.dbversion order by dbversion_id desc limit 1"
cat $FILENAME | while IFS=";" read INSTANCENAME DBHOST DATABASE LOGIN PASSWORD
do
	if (test "$INSTANCENAME" != "instance") ; then
		echo "$INSTANCENAME"
		ADDRESS=postgresql://$LOGIN:$PASSWORD@$DBHOST/$DATABASE
		VERSION=`psql $ADDRESS -c "$SQL" -t|xargs`
		cd $FOLDERINSTALL
		SCRIPT="install/upgradedb-from-$VERSION.sh"
		source $SCRIPT
		echo "$INSTANCENAME done"
		echo " "
	fi
done
