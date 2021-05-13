#!/bin/bash -ex
DUMPFILE="mydb-$(date +%s).dump"
export BUCARDO_DEBUG=4

[ -z $BUCARDO_OLD_HOSTNAME ] && echo "Please set BUCARDO_OLD_HOSTNAME" && exit 1
[ -z $BUCARDO_OLD_USERNAME ] && echo "Please set BUCARDO_OLD_USERNAME" && exit 1
[ -z $BUCARDO_OLD_PASSWORD ] && echo "Please set BUCARDO_OLD_PASSWORD" && exit 1
[ -z $BUCARDO_OLD_DATABASE ] && echo "Please set BUCARDO_OLD_DATABASE" && exit 1

[ -z $BUCARDO_NEW_HOSTNAME ] && echo "Please set BUCARDO_NEW_HOSTNAME" && exit 1
[ -z $BUCARDO_NEW_USERNAME ] && echo "Please set BUCARDO_NEW_USERNAME" && exit 1
[ -z $BUCARDO_NEW_PASSWORD ] && echo "Please set BUCARDO_NEW_PASSWORD" && exit 1
[ -z $BUCARDO_NEW_DATABASE ] && echo "Please set BUCARDO_NEW_DATABASE" && exit 1

# Setup an alias for bucardo the explicitly specifies the local password so we don't have to retype it each time
bucardo_cmd() {
        bucardo -h localhost -p 5432 -P $BUCARDO_LOCAL_PASSWORD $@
}
export -f bucardo_cmd

# Create the .pgpass file in order for postgres CLI to not ask for password each time
echo "" > ~/.pgpass
cat >> ~/.pgpass <<EOF
$BUCARDO_OLD_HOSTNAME:5432:*:$BUCARDO_OLD_USERNAME:$BUCARDO_OLD_PASSWORD
$BUCARDO_NEW_HOSTNAME:5432:*:$BUCARDO_NEW_USERNAME:$BUCARDO_NEW_PASSWORD
EOF
# Set correct permissions on the .pgpass file
chmod 0600 ~/.pgpass

# Create the database and the user accounts in the new (empty) database
envsubst < setup_new_database.template > setup_new_database.sql
psql -h ${BUCARDO_NEW_HOSTNAME} -U ${BUCARDO_NEW_USERNAME} -f postgres setup_new_database.sql

# Setup Bucardo multi-master replication
# XXX: Unfortunately Bucardo does not read the .pgpass file,
#      so we must explicitly specify the password in the command.
bucardo_cmd add db source_db \
        dbhost=$BUCARDO_OLD_HOSTNAME \
        dbport=5432 \
        dbname=$BUCARDO_OLD_DATABASE \
        dbuser=$BUCARDO_OLD_USERNAME \
        dbpass=$BUCARDO_OLD_PASSWORD
bucardo_cmd add db target_db \
        dbhost=$BUCARDO_NEW_HOSTNAME \
        dbport=5432 \
        dbname=$BUCARDO_NEW_DATABASE \
        dbuser=$BUCARDO_NEW_USERNAME \
        dbpass=$BUCARDO_NEW_PASSWORD

# List the bucardo databases
echo "The bucardo databases are:"
bucardo_cmd list databases

# Setup bucardo to replicate all tables and all sequences
bucardo_cmd add table all --db=source_db --herd=my_herd
bucardo_cmd add sequence all --db=source_db --herd=my_herd

# Remove any unused tables or the ones that don't have indexes
bucardo_cmd remove table public.table_foo
bucardo_cmd remove table public.table_bar

# Setup bucardo dbgroups
bucardo_cmd add dbgroup my_group
bucardo_cmd add dbgroup my_group source_db:source
bucardo_cmd add dbgroup my_group target_db:source

# Transfer the database schema
pg_dump -v -h $BUCARDO_OLD_HOSTNAME -U $BUCARDO_OLD_USERNAME --schema-only $BUCARDO_OLD_DATABASE --file=schema.sql
psql -h $BUCARDO_NEW_HOSTNAME -U $BUCARDO_NEW_USERNAME -d $BUCARDO_OLD_DATABASE -f schema.sql

# Setup bucardo sync (autokick=0) ensures that nothing is transfered yet
bucardo_cmd add sync my_sync_2021 herd=my_herd dbs=my_group autokick=0

# Migrate the data using compression in order to minimize file size. Make sure
# that you don't transfer Bucardo's data or anything else that is not managed by
# you.
echo "Dumping data to compressed file"
time pg_dump -v \
    -U $BUCARDO_OLD_USERNAME \
    -h $BUCARDO_OLD_HOSTNAME \
    --file=$DUMPFILE \
    -N bucardo -N schema_baz \
    -Fc \
    $BUCARDO_OLD_DATABASE
echo "Restoring data from compressed file"
# Treat the new database as replica until the data restoration is over, to avoid
# re-running triggers. `-j 8` is the parallelization factor, you can change it
# according to your system's number of CPUs.
export PGOPTIONS='-c session_replication_role=replica'
time pg_restore -v \
    -U $BUCARDO_NEW_USERNAME \
    -h $BUCARDO_NEW_HOSTNAME \
    -j 8 \
    --data-only \
    -d $BUCARDO_NEW_DATABASE \
    $DUMPFILE
export PGOPTIONS=''

# Reset autokick flag and start continuous multi-master replication
echo "Starting Bucardo"
bucardo_cmd start
bucardo_cmd update sync bg_sync_2021 autokick=1
bucardo_cmd reload config
bucardo_cmd restart
