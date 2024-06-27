#!/bin/bash
if [ -f /home/db2inst1/sqllib/db2profile ]; then
    . /home/db2inst1/sqllib/db2profile
else
    echo "db2profile niet gevonden"
    exit 1
fi

db2 connect to qis

db2 "call mon.clean_all(32)"

db2 disconnect current;