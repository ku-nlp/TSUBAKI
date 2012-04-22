#!/bin/sh

CONFIGURE_FILE_IN=cgi/configure.in
CONFIGURE_FILE=cgi/configure

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
