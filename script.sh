#!/bin/sh

status=$(sudo systemctl is-active docker)

# check docker is running
if [ "$status" != "active" ]; then
  echo "Docker is not $status. starting docker"
  sudo systemctl start docker > /dev/null 2>&1
fi
 # check docker is running
 sleep 2

# Setting all the variables
export PG_ADMIN_NAME=root
export PG_ADMIN_PASSWORD=mypassword
export PG_PORT=5432
export MINIO_ROOT_USER=minioadmin
export MINIO_ROOT_PASSWORD=minioadmin123
export ORG_NAME="org"
export AUTH_METHOD_NAME="password"
export ADMIN_LOGIN_UID="orgadmin"

# Setup PostgresSQl Database
setupdb() {
    echo "Setting up PostgreSQL Database"

    # Run PostgreSQL in a Docker container
    docker run --name postgres \
     -p $PG_PORT:$PG_PORT \
     --rm \
     -e POSTGRES_USER=$PG_ADMIN_NAME \
     -e POSTGRES_PASSWORD=$PG_ADMIN_PASSWORD \
     -d postgres

     # Wait for PostgreSQL to be ready (max 5 seconds)
    echo "Waiting for PostgreSQL to be ready..."
    counter=0
    until docker exec postgres pg_isready -U $PG_ADMIN_NAME > /dev/null 2>&1; do
      sleep 1
      counter=$((counter + 1))
      if [ $counter -ge 5 ]; then
        echo "PostgreSQL did not start within 5 seconds"
        exit 1
      fi
    done
    echo "PostgreSQL is ready!"

    # Setup psql function to the container to make it easier to do CLI commands to the postgresql pod
    psqld() {
        docker exec -i postgres psql "$@"
    }

    # Configure the name of the database role used for the Vault database engine
    export PGROLE=readonly

    # Create a database role for Vault database engine to use
    psqld -U $PG_ADMIN_NAME -c "CREATE ROLE \"$PGROLE\" NOINHERIT;"

    # Grant the ability to read all tables to the role
    psqld -U $PG_ADMIN_NAME -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$PGROLE\";"

    # list users and roles and verify that the role is created
    psqld -U $PG_ADMIN_NAME -c '\x auto;' -c "\dg"

    # create database boundary - needed for boundaru
    psqld -U $PG_ADMIN_NAME -c "CREATE DATABASE boundary;"

    # Verify database was created
    echo "Verifying boundary database creation..."
    DB_EXISTS=$(psqld -U $PG_ADMIN_NAME -t -c "SELECT 1 FROM pg_database WHERE datname='boundary';" | tr -d '[:space:]')
    if [ "$DB_EXISTS" = "1" ]; then
        echo "Database 'boundary' created successfully"
    else
        echo "Failed to create database 'boundary'"
        exit 1
    fi
}

#MinIO URL will be  http://localhost:9000
setupminio() { 
  echo "Setting up MinIO S3-Compatible server"
  docker run -d -p 9000:9000 -p 9001:9001 \
    --name minio \
    -v ~/minio/data:/data \
    -e MINIO_ROOT_USER=$MINIO_ROOT_USER \
    -e MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD \
    quay.io/minio/minio server /data --console-address ":9001"

  # Wait for MinIO to be ready (max 5 seconds)
  echo "Waiting for MinIO to be ready..."
  counter=0
  until curl -s http://localhost:9000/minio/health/ready > /dev/null 2>&1; do
    sleep 1
    counter=$((counter + 1))
    if [ $counter -ge 5 ]; then
      echo "MinIO did not start within 5 seconds"
      exit 1
    fi
  done
  echo "MinIO is ready!"
}

setupboundarycontroller() {
echo "Setting up Boundary Controller"
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

# Verify controller.hcl was created
if [ -f "controller.hcl" ]; then
  echo "controller.hcl created successfully"
else
  echo "Failed to create controller.hcl"
  exit 1
fi

# Bootstrap boundary controller
cat << EOF > recovery.hcl
kms "aead" {
  purpose = "recovery"
  aead_type = "aes-gcm"
  key = "JehZ4hnGr2QA1i4W94jzPlLOFi6LcAdCRsI73Quqd7M="
  key_id = "global_recovery"
}
EOF

# Verify recovery.hcl was created
if [ -f "recovery.hcl" ]; then
  echo "recovery.hcl created successfully"
else
  echo "Failed to create recovery.hcl"
  exit 1
fi

# Initialize Boundary database
docker run --rm \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  hashicorp/boundary:latest \
  boundary database init -config=/boundary/controller.hcl

# Run Boundary Controller in Docker
docker run -d  \
  --name boundary-controller \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
  -v "$(pwd)/recovery.hcl":/boundary/recovery.hcl \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  -e "BOUNDARY_PASSWORD=mypassword" \
  hashicorp/boundary:latest \
  boundary server -config=/boundary/controller.hcl

  # Wait for Boundary to be ready (max 30 seconds)
  echo "Waiting for Boundary Controller to be ready..."
  counter=0
  until [ "$(curl -s -k -o /dev/null -w '%{http_code}' http://localhost:9203/health)" = "200" ]; do
    sleep 1
    counter=$((counter + 1))
    if [ $counter -ge 5 ]; then
      echo "Boundary Controller did not start within 5 seconds"
      exit 1
    fi
  done
  echo "Boundary Controller is ready!"
}

initboundarycontroller() {

  boundary() {
        docker exec -i boundary-controller boundary "$@"
  }
  echo "Initializing Boundary Controller"
   # Create scope and capture the ID  
  export SCOPE_ID=$(boundary scopes create \
    -name $ORG_NAME \
    -scope-id 'global' \
    -recovery-config /boundary/recovery.hcl \
    -skip-admin-role-creation \
    -skip-default-role-creation \
    -format json | jq -r '.item.id')

  echo "Scope ID is: $SCOPE_ID"

  # create an auth method
  export AUTH_METHOD_ID=$(boundary auth-methods create password \
    -recovery-config /boundary/recovery.hcl \
    -scope-id $SCOPE_ID \
    -name $AUTH_METHOD_NAME \
    -description 'My password auth method' \
    -format json | jq -r '.item.id')

  echo "Auth Method ID is: $AUTH_METHOD_ID"

  # create a login account
  export LOGIN_ACCOUNT_ID=$(boundary accounts create password \
    -recovery-config /boundary/recovery.hcl \
    -login-name $ADMIN_LOGIN_UID\
    -password env://BOUNDARY_PASSWORD \
    -auth-method-id "$AUTH_METHOD_ID" \
    -format json | jq -r '.item.id')

   echo "Login Account ID is: $LOGIN_ACCOUNT_ID"

# Create a user
  export USER_ID=$(boundary users create -scope-id $SCOPE_ID \
    -recovery-config /boundary/recovery.hcl \
    -name "demouser" \
    -description "My user!" \
    -format json | jq -r '.item.id')

   echo "User ID is: $USER_ID"

 # Correlate the user to the login account
  boundary users add-accounts \
    -recovery-config /boundary/recovery.hcl \
    -id $USER_ID \
    -account $LOGIN_ACCOUNT_ID

# create org admin role at the global scope for admin user
export ROLE_ID=$(boundary roles create -name 'org_admin3' \
  -recovery-config /boundary/recovery.hcl \
  -scope-id 'global' \
  -format json | jq -r '.item.id')

echo "Role ID is: $ROLE_ID"

# grant the role to the scope "global" -> This role will have access to all scopes
export GRANT_SCOPE_ID=$(boundary roles set-grant-scopes \
  -recovery-config /boundary/recovery.hcl \
  -id $ROLE_ID \
  -grant-scope-id $SCOPE_ID \
  -format json | jq -r '.item.id')

echo "Grant Scope ID is: $GRANT_SCOPE_ID"

# add grants to the role
boundary roles add-grants -id $ROLE_ID \
  -recovery-config /boundary/recovery.hcl \
  -grant 'ids=*;type=*;actions=*' \ 
  -format json | jq -r '.item.id'

# assign user account to the role
boundary roles add-principals -id $ROLE_ID \
  -recovery-config /boundary/recovery.hcl \
  -principal $USER_ID


# check auth is successful
echo "Authenticating to Boundary Controller"
boundary authenticate password \
  -auth-method-id=$AUTH_METHOD_ID \
  -login-name=$ADMIN_LOGIN_UID \
  -password=env://BOUNDARY_PASSWORD \
  -format json 
}

# calling function
setupdb
setupminio
setupboundarycontroller
initboundarycontroller

# Add alias to ~/.bashrc for use outside this script
if ! grep -q "alias psqld=" ~/.bashrc; then
    echo 'alias psqld="docker exec -it postgres psql"' >> ~/.bashrc
    . ~/.bashrc
    echo "Added psqld alias to ~/.bashrc (available in new terminal sessions)"
fi

if ! grep -q "alias boundary=" ~/.bashrc; then
    echo 'alias boundary="docker exec -it boundary-controller boundary"' >> ~/.bashrc
    . ~/.bashrc
    echo "Added boundary alias to ~/.bashrc (available in new terminal sessions)"
fi


export POSTGRES_DB_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' postgres)
echo "Postgres IP Address is: $POSTGRES_DB_IP"
echo "Postgres Role is: $PGROLE"
echo "Postgres Admin Username is: $PG_ADMIN_NAME"
echo "Postgres Admin Password is: $PG_ADMIN_PASSWORD"

# Printout MinIO details
echo "Minio Admin Username is: $MINIO_ROOT_USER"
echo "Minio Admin Password is: $MINIO_ROOT_PASSWORD"
echo "MinIO Console URL is  http://localhost:9001"
echo "MinIO API URL is  http://localhost:9000"

# Print Boundary details
echo "Boundary Controller API URL is: http://localhost:9200"
echo "Boundary Controller Login Admin User ID is: $ADMIN_LOGIN_UID and Password is: mypassword"
echo "Boundary Controller ORG_NAME is: $ORG_NAME"
echo "Boundary Controller AUTH_METHOD_NAME is: $AUTH_METHOD_NAME"


# Setup MinIO S3-Compatible server
# wget https://dl.min.io/server/minio/release/linux-amd64/minio
# chmod +x minio
# sudo mv minio /usr/local/bin/

# Setup MinIO Client
# wget https://dl.min.io/client/mc/release/linux-amd64/mc
# chmod +x mc
# sudo mv mc /usr/local/bin/

# minio server /data

# Download and install HashiCorp Boundary Controller
# wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
# echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
# sudo apt update && sudo apt install boundary


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

# Run Boundary Worker in Docker
docker run -d \
  --name boundary-worker \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/worker.hcl":/boundary/worker.hcl \
  hashicorp/boundary:latest \
  boundary server -config=/boundary/worker.hcl





