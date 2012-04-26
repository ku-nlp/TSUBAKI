#!/bin/sh

CONFIGURE_FILE_IN=cgi/configure.in
CONFIGURE_FILE=cgi/configure
TSUBAKI_CONF_FILE_IN=conf/tsubaki.conf.in
TSUBAKI_CONF_FILE=conf/tsubaki.conf
PORTS_FILE_IN=data/PORTS.SYN.in
PORTS_FILE=data/PORTS.SYN

CWD=$(pwd)

NAME_LIST="
SearchEnginePath
HOME
"

SearchEnginePath=$CWD

# getopts
# 

SED_STR=
for name in $NAME_LIST
do
    eval "val=\${${name}}"
    echo "setting \"$name\" to \"$val\""
    SED_STR=${SED_STR}"s#@${name}@#${val}#g;"
done

echo "generating '${CONFIGURE_FILE}' ... "
sed -e "${SED_STR}" $CONFIGURE_FILE_IN > $CONFIGURE_FILE
echo "done."
echo "generating '${TSUBAKI_CONF_FILE}' ... "
sed -e "${SED_STR}" $TSUBAKI_CONF_FILE_IN > $TSUBAKI_CONF_FILE
echo "done."
echo "generating '${PORTS_FILE}' ... "
sed -e "${SED_STR}" $PORTS_FILE_IN > $PORTS_FILE
echo "done."
