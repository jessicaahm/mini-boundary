#!/bin/sh

sudo apt update
sudo apt install curl ca-certificates gnupg -y
sudo apt install docker.io -y
sudo apt install postgresql-client-common -y
sudo apt install postgresql-client -y

# Add current user to docker group
sudo usermod -aG docker $USER

# Log out and log back in, or run:
newgrp docker

# Test docker without sudo
docker ps

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
alias psqld="sudo docker exec -it postgres psql"

# Configure the name of the database role used for the Vault database engine
export PGROLE=readonly

# Create a database role for Vault database engine to use
psqld -U $PG_ADMIN_NAME -c "CREATE ROLE \"$PGROLE\" NOINHERIT;"

# Grant the ability to read all tables to the role
psqld -U $PG_ADMIN_NAME -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$PGROLE\";"

# list users and roles and verify that the role is created
psqld -U $PG_ADMIN_NAME -c '\x auto;' -c "\dg"

psqld -U $PG_ADMIN_NAME -c "CREATE DATABASE boundary;"
#psql "postgresql://root:mypassword@172.17.0.2:5432/boundary?sslmode=disable" -c "\conninfo"

# As both Vault and PostgreSQL is running on docker, Boundary will be connecting to PostgreSQL via the docker bridge network
# Obtain IP address of the postgres database for configuration
export POSTGRES_DB_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' postgres)
echo "Postgres IP Address is: $POSTGRES_DB_IP"
echo "Postgres Role is: $PGROLE"
echo "Postgres Admin Username is: $PG_ADMIN_NAME"
echo "Postgres Admin Password is: $PG_ADMIN_PASSWORD"

# Setup MinIO S3-Compatible server
# wget https://dl.min.io/server/minio/release/linux-amd64/minio
# chmod +x minio
# sudo mv minio /usr/local/bin/

# Setup MinIO Client
# wget https://dl.min.io/client/mc/release/linux-amd64/mc
# chmod +x mc
# sudo mv mc /usr/local/bin/

export MINIO_ROOT_USER=minioadmin
export MINIO_ROOT_PASSWORD=minioadmin123

# minio server /data
docker run -d -p 9000:9000 -p 9001:9001 \
  --name minio \
  -v ~/minio/data:/data \
  -e MINIO_ROOT_USER=$MINIO_ROOT_USER \
  -e MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD \
  quay.io/minio/minio server /data --console-address ":9001"

# MinIO URL will be  http://localhost:9000

# Download and install HashiCorp Boundary Controller
# wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
# echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
# sudo apt update && sudo apt install boundary

sudo cat << EOF > controller.hcl
controller {
  name = "boundary-controller"
  description = "Demo Boundary Controller"
  database {
    url = "postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable"
  }
}

listener "tcp" {
  address = "0.0.0.0:9200"
  purpose = "api"
  tls_disable = true
}

listener "tcp" {
  address = "0.0.0.0:9201"
  purpose = "cluster"
  tls_disable = true
}

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "ops"
  tls_disable = true
}

kms "aead" {
  purpose = "root"
  aead_type = "aes-gcm"
  key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
  key_id = "global_root"
}

kms "aead" {
  purpose = "recovery"
  aead_type = "aes-gcm"
  key = "JehZ4hnGr2QA1i4W94jzPlLOFi6LcAdCRsI73Quqd7M="
  key_id = "global_recovery"
}
EOF

# Create Boundary Worker configuration
sudo cat << EOF > worker.hcl
listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
  tls_disable = true
}

worker {
  name = "boundary-worker-1"
  description = "Demo Boundary Worker"
  initial_upstreams = ["127.0.0.1:9201"]
  public_addr = "127.0.0.1"
}

kms "aead" {
  purpose = "worker-auth"
  aead_type = "aes-gcm"
  key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
  key_id = "global_root"
}
EOF

# Initialize Boundary database
docker run --rm \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  hashicorp/boundary:latest \
  boundary database init -config=/boundary/controller.hcl

# Run Boundary Controller in Docker
# docker run --rm  \
#   --name boundary-controller \
#   --network host \
#   --cap-add IPC_LOCK \
#   -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
#   -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
#   hashicorp/boundary:latest \
#   boundary server -config=/boundary/controller.hcl

docker run \
  --name boundary-controller \
  --network host \
  --cap-add IPC_LOCK \
  -p 9200:9200 \
  -p 9201:9201 \
  -p 9202:9202 \
  -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  hashicorp/boundary:latest \
  boundary server -config=/boundary/controller.hcl

# Run Boundary Worker in Docker
docker run -d \
  --name boundary-worker \
  --network host \
  -v "$(pwd)/worker.hcl":/boundary/worker.hcl \
  hashicorp/boundary:latest \
  boundary server -config=/boundary/worker.hcl
