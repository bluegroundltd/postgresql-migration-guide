#!/bin/bash
if ! command -v pgdatadiff &> /dev/null
then
    sudo apt install libpq-dev python3-dev python3-pip
    pip3 install git+https://github.com/andrikoz/pgdatadiff.git
fi
pgdatadiff \
    --firstdb=postgres://$BUCARDO_OLD_USERNAME:$BUCARDO_OLD_PASSWORD@$BUCARDO_OLD_HOSTNAME/$BUCARDO_OLD_DATABASE \
    --seconddb=postgres://$BUCARDO_NEW_USERNAME:$BUCARDO_NEW_PASSWORD@$BUCARDO_NEW_HOSTNAME/$BUCARDO_NEW_DATABASE \
    --only-data \
    --exclude-tables=table_foo,table_bar
