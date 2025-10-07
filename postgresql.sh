#!/bin/sh

sudo apt update
sudo apt install curl ca-certificates gnupg -y
sudo apt install docker.io -y
sudo apt install postgresql-client-common -y
sudo apt install postgresql-client -y

export PG_ADMIN_NAME=root
export PG_ADMIN_PASSWORD=mypassword
export PG_PORT=5432

docker run --name postgres \
     -p $PG_PORT:$PG_PORT \
     --rm \
     -e POSTGRES_USER=$PG_ADMIN_NAME \
     -e POSTGRES_PASSWORD=$PG_ADMIN_PASSWORD \
     -d postgres

# Setup psql alias to the container to make it easier to do CLI commands to the postgresql pod
alias psqld="docker exec -it postgres psql"
