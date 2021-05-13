#!/bin/bash -ex

#
# Note: Need to run this as root
#

[ -z $BUCARDO_LOCAL_PASSWORD ] && echo "Plase set BUCARDO_LOCAL_PASSWORD" && exit 1

# Install prerequisites
apt update
apt install -y \
	cpanminus \
	gcc \
	libdbi-perl \
	libpq-dev \
	make \
	postgresql \
	postgresql-client-common \
	postgresql-plperl-12

# Create bucardo user in the local Postgresql
sudo -u postgres psql -w postgres <<EOF
CREATE USER bucardo WITH LOGIN SUPERUSER ENCRYPTED PASSWORD '$BUCARDO_LOCAL_PASSWORD';
EOF

# Create bucardo database in the local Postgresql
sudo -u postgres psql -w postgres <<EOF
CREATE DATABASE bucardo;
EOF

# Install Perl modules required by Bucardo
cpanm CGI
cpanm DBD::Pg
cpanm DBIx::Safe
cpanm Encode::Locale

# Download and install Bucardo from source
curl -L https://github.com/bucardo/bucardo/archive/5.5.0.tar.gz -o bucardo.tar.gz
tar -zxvf bucardo.tar.gz
pushd bucardo-5.5.0
perl Makefile.PL
make
make install
popd

mkdir -p /var/run/bucardo
mkdir -p /var/log/bucardo
