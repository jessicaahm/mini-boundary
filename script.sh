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
export ADMIN_LOGIN_UID="admin"
export ROLE_NAME="orgadmin"
export ADMIN_LOGIN_PWD="mypassword"
export VM_IP_ADDR="44.203.31.9"
export BOUNDARY_PATH="/boundary"

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

    # create database boundary - needed for boundary
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
# Copy license files to boundary for enterprise features
# docker cp /boundary/boundary.hclic vault:/tmp/boundary.hclic

sudo cat << EOF > ./controller.hcl
    controller {
      name = "boundary-controller"
      description = "Demo Boundary Controller"
      database {
        url = "postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable"
      }
      license = "file:///boundary/boundary.hclic"
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

    kms "aead" {
    purpose = "worker-auth"
    aead_type = "aes-gcm"
    key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
    key_id = "global_worker-auth"
    }

    kms "aead" {
    purpose = "bsr"
    aead_type = "aes-gcm"
    key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
    key_id = "bsr"
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
cat << EOF > ./recovery.hcl
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
  -v "$BOUNDARY_PATH"/boundary.hclic:/boundary/boundary.hclic:ro \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  hashicorp/boundary-enterprise:latest \
  boundary database init -config=/boundary/controller.hcl

# Run Boundary Controller in Docker
docker run -d  \
  --name boundary-controller \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/controller.hcl":/boundary/controller.hcl \
  -v "$(pwd)/recovery.hcl":/boundary/recovery.hcl \
  -v "/boundary/boundary.hclic":/boundary/boundary.hclic \
  -e "BOUNDARY_POSTGRES_URL=postgresql://${PG_ADMIN_NAME}:${PG_ADMIN_PASSWORD}@localhost:${PG_PORT}/boundary?sslmode=disable" \
  -e "BOUNDARY_PASSWORD=$ADMIN_LOGIN_PWD" \
  hashicorp/boundary-enterprise:latest \
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
        docker exec -it boundary-controller boundary "$@"
  }
  echo "Initializing Boundary Controller"
  
  # Create "org" scope and capture the ID  
  export SCOPE_ID=$(boundary scopes create \
    -name $ORG_NAME \
    -scope-id 'global' \
    -recovery-config /boundary/recovery.hcl \
    -skip-admin-role-creation \
    -skip-default-role-creation \
    -format json | jq -r '.item.id')
  echo "Scope ID is: $SCOPE_ID"

  #create project
  export PROJECT_ID=$(boundary scopes create -name 'project' -scope-id $SCOPE_ID \
  -recovery-config /boundary/recovery.hcl \
  -skip-admin-role-creation \
  -skip-default-role-creation \
  -format json | jq -r '.item.id')
  echo "Project ID is: $PROJECT_ID"

  # create an auth method in scope global
  export AUTH_METHOD_ID=$(boundary auth-methods create password \
    -recovery-config /boundary/recovery.hcl \
    -scope-id global \
    -name $AUTH_METHOD_NAME \
    -description 'My password auth method' \
    -format json | jq -r '.item.id')
  echo "Auth Method ID is: $AUTH_METHOD_ID"

  # Create a login account for the admin user
  export LOGIN_ACCOUNT_ID=$(boundary accounts create password \
    -recovery-config /boundary/recovery.hcl \
    -login-name $ADMIN_LOGIN_UID\
    -password env://BOUNDARY_PASSWORD \
    -auth-method-id "$AUTH_METHOD_ID" \
    -format json | jq -r '.item.id')

   echo "Login Account ID is: $LOGIN_ACCOUNT_ID"

# Create a user
  export USER_ID=$(boundary users create -scope-id global \
    -recovery-config /boundary/recovery.hcl \
    -name "myuser" \
    -description "My user!" \
    -format json | jq -r '.item.id')

   echo "User ID is: $USER_ID"

 # Correlate the user to the login account
  boundary users add-accounts \
    -recovery-config /boundary/recovery.hcl \
    -id $USER_ID \
    -account $LOGIN_ACCOUNT_ID

# create admin role at the global scope for admin user
export ROLE_ID=$(boundary roles create -name $ROLE_NAME \
  -recovery-config /boundary/recovery.hcl \
  -scope-id 'global' \
  -format json | jq -r '.item.id')

echo "Role ID is: $ROLE_ID"

# grant the role to the scope "global" -> This role will have access to all scopes
export GRANT_SCOPE_ID=$(boundary roles set-grant-scopes \
  -recovery-config /boundary/recovery.hcl \
  -id $ROLE_ID \
  -grant-scope-id "global" \
  -format json | jq -r '.item.id')

boundary roles add-grant-scopes \
  -recovery-config /boundary/recovery.hcl \
  -id $ROLE_ID -grant-scope-id "this" \
  -grant-scope-id "descendants"

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
echo "To authenticate to Boundary Controller use the following command:"
echo "----START AUTH COMMAND----"
echo "boundary authenticate password -auth-method-id=$AUTH_METHOD_ID -login-name=$ADMIN_LOGIN_UID -password=env://BOUNDARY_PASSWORD"
echo "----END AUTH COMMAND----"
# boundary authenticate password \
#   -auth-method-id=$AUTH_METHOD_ID \
#   -login-name=$ADMIN_LOGIN_UID \
#   -password=env://BOUNDARY_PASSWORD \
#   -format json | jq '.'

boundary authenticate password \
  -auth-method-id=$AUTH_METHOD_ID \
  -login-name=$ADMIN_LOGIN_UID \
  -password=env://BOUNDARY_PASSWORD \
  -format json | jq '.'
}

setupboundaryworker() {
  echo "Setting up Boundary Worker"
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
  recording_storage_path = "/tmp/boundary-recordings"
  recording_storage_minimum_available_capacity = "50MB"
  public_addr = "$VM_IP_ADDR"
  tags {
    type = ["worker", "local"]
  }
}

kms "aead" {
  purpose = "worker-auth"
  aead_type = "aes-gcm"
  key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
  key_id = "global_worker-auth"
}

kms "aead" {
  purpose = "bsr"
  aead_type = "aes-gcm"
  key = "DfvbhCAGba7TvdvpiVrbh2IVTQlhoC7t/RXGvfRJlVI="
  key_id = "bsr"
}
EOF

# Run Boundary Worker in Docker
docker run -d \
  --name boundary-worker \
  --network host \
  --cap-add IPC_LOCK \
  -v "$(pwd)/worker.hcl":/boundary/worker.hcl \
  hashicorp/boundary-enterprise:latest \
  boundary server -config=/boundary/worker.hcl

  boundary() {
        docker exec -it boundary-controller boundary "$@"
  }

# Get Worker Auth Registration Request
echo "Waiting for worker auth token..."
sleep 5
export WORKER_AUTH_TOKEN=$(docker logs boundary-worker 2>&1 | grep "Worker Auth Registration Request" | sed 's/Worker Auth Registration Request: *//' | xargs)

if [ -z "$WORKER_AUTH_TOKEN" ]; then
  echo "Failed to get worker auth token. Check worker logs:"
  docker logs boundary-worker 2>&1 | tail -20
  exit 1
fi
echo "Worker Auth Registration Request is: $WORKER_AUTH_TOKEN"

echo "Checking AUTH_METHOD_ID again: $AUTH_METHOD_ID"
echo "Checking ADMIN LOGIN UID again: $ADMIN_LOGIN_UID"

export BOUNDARY_TOKEN=$(boundary authenticate password \
  -auth-method-id="$AUTH_METHOD_ID" \
  -login-name="$ADMIN_LOGIN_UID"\
  -password=env://BOUNDARY_PASSWORD \
  -format json | jq  -r '.item.attributes.token')

echo "Boundary Token is: $BOUNDARY_TOKEN"

docker exec -e "WORKER_AUTH_TOKEN=$WORKER_AUTH_TOKEN" -e "BOUNDARY_TOKEN=$BOUNDARY_TOKEN" boundary-worker sh -c '
  export BOUNDARY_PASSWORD="mypassword"
  echo "IF FAIL : RUN MANUALLY"
  echo "export BOUNDARY_TOKEN=$BOUNDARY_TOKEN"
  echo "export WORKER_AUTH_TOKEN=$WORKER_AUTH_TOKEN"

  boundary workers create worker-led -worker-generated-auth-token "$WORKER_AUTH_TOKEN" -token "env://BOUNDARY_TOKEN"
'

# export BOUNDARY_TOKEN=$(boundary authenticate password \
#   -auth-method-id="$AUTH_METHOD_ID" \
#   -login-name=$ADMIN_LOGIN_UID \
#   -password=env://BOUNDARY_PASSWORD \
#   -format json | jq  -r '.item.attributes.token')



# echo "Boundary Token is: $BOUNDARY_TOKEN"

# # Authentication
# boundary workers create worker-led -worker-generated-auth-token "$WORKER_AUTH_TOKEN"

# docker exec -it boundary-controller boundary workers create worker-led -token "env://BOUNDARY_TOKEN" -worker-generated-auth-token "pdZ5SAAebKa9DmnokkNu5EuBPe17XuPEimxzwMkactdmR8zy5kNrDJ2tZAWjEpyL9d5v1HLV3v1dXTu8Hm9sXMrLWunf45zUNtkEabAt3WtuMwmszm8oYmYeCCHCSbYgrom7hALSCe2jxmYhunMoJMbuxGRgpAuFxwNzg7yiEX9dJ6zYqXm7d2hHiEKxKQ4wKzpD8M2Gb8NQbzQtbPyiZaSmpVsEBq76SgHAUGzxx9pkFJRXtvRwCWXeW2PRVcZhhj5sbFwfibuf4WpQ9Cv8dHnnwzGnrYZDwpYYU3d"

}

setupdb
#setupminio
setupboundarycontroller
initboundarycontroller
setupboundaryworker

# Add alias to ~/.bashrc for use outside this script
# if ! grep -q "alias psqld=" ~/.bashrc; then
#     echo 'alias psqld="docker exec -it postgres psql"' >> ~/.bashrc
#     . ~/.bashrc
#     echo "Added psqld alias to ~/.bashrc (available in new terminal sessions)"
# fi

# if ! grep -q "alias mc=" ~/.bashrc; then
#     echo 'alias mc="docker exec -it minio mc"' >> ~/.bashrc
#     . ~/.bashrc
#     echo "Added psqld alias to ~/.bashrc (available in new terminal sessions)"
# fi

# if ! grep -q "alias boundary=" ~/.bashrc; then
#     echo 'alias boundary="docker exec -it boundary-controller boundary"' >> ~/.bashrc
#     . ~/.bashrc
#     echo "Added boundary alias to ~/.bashrc (available in new terminal sessions)"
# fi

# if ! grep -q "alias vault=" ~/.bashrc; then
#     echo 'alias vault="docker exec -it vault vault"' >> ~/.bashrc
#     . ~/.bashrc
#     echo "Added vault alias to ~/.bashrc (available in new terminal sessions)"
# fi

# if ! grep -q "alias worker=" ~/.bashrc; then
#     echo 'alias worker="docker exec -it boundary-worker boundary"' >> ~/.bashrc
#     . ~/.bashrc
#     echo "Added worker alias to ~/.bashrc (available in new terminal sessions)"
# fi


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







