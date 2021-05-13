#!/bin/bash -ex

envsubst < uninstall.template > uninstall.sql

psql -h ${BUCARDO_OLD_HOSTNAME} -U ${BUCARDO_OLD_USERNAME} -d ${BUCARDO_OLD_DATABASE} -f uninstall.sql
