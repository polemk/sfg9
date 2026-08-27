#!/bin/bash
# script for installing pgvector on ubuntu/debian with postgresql 14+
# Usage: ./install_pgvector.sh

set -e

echo "Updating package lists..."
sudo apt-get update

echo "Finding installed PostgreSQL version..."
PG_VERSION=$(psql -V | egrep -o '[0-9]{2}' | head -n 1)

if [ -z "$PG_VERSION" ]; then
    echo "PostgreSQL not found! Please install it first."
    exit 1
fi

echo "Detected PostgreSQL version: $PG_VERSION"

echo "Installing postgresql-$PG_VERSION-pgvector..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "postgresql-$PG_VERSION-pgvector"

echo "Done! You can now run migrations to enable the 'vector' extension."
