#!/bin/bash
FILENAME="/var/local/collec-science/multi-instances/instances.csv"
BASEFOLDER="/var/www/collec2App/collec-science"
NEWFOLDER="/var/www/collec2App"
NEWAPP="/var/www/collec2App/collec-science/public"
CURRENT="${PWD}"
cat $FILENAME | while IFS=";" read INSTANCENAME DBHOST DATABASE LOGIN PASSWORD
do
        if (test "$INSTANCENAME" != "instance") ; then
                if [ -d $NEWFOLDER/$INSTANCENAME ] ; then
                        export envPath=$NEWFOLDER/$INSTANCENAME
                #       echo $INSTANCENAME
                #       echo $envPath
                        php $NEWAPP/index.php collectionsGenerateMail
                #else
                #       cd $BASEFOLDER/$INSTANCENAME/bin
                #       php modules/param/collectionsGenerateMail.php
                fi
        fi
done
cd $CURRENT
