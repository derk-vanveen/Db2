#!/bin/bash
if [ -f /home/db2inst1/sqllib/db2profile ]; then
    . /home/db2inst1/sqllib/db2profile
else
    echo "db2profile niet gevonden"
    exit 1
fi

db2 connect to qis user monuser using monuser

db2 "call mon.insert_all()"

db2 disconnect current