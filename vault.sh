#!/bin/bash
# This need Vault CLI installed

# Vault Setup
export VM_IP_ADDR="44.198.55.208"
export VAULT_TOKEN=myroot
export VAULT_PATH="/tmp"

# Set up vault
setupvault() {
  echo "Setting up Vault"

  sudo mkdir /tmp/vault
  sudo mkdir /tmp/vault/{config,data}

  # Run Vault in a Docker Container Server
  sudo tee /tmp/vault/config/vault-server.hcl <<EOF
    ui = true
    disable_mlock = true
    listener "tcp" {
    tls_disable = 1
    address = "[::]:8200"
    cluster_address = "[::]:8201"
    }

    storage "raft" {
    path = "/vault/file"
    node_id = "node1"
    }
EOF

sudo docker run \
      --name=vault \
      -p 8200:8200 \
      -e VAULT_ADDR="http://127.0.0.1:8200" \
      -e VAULT_CLUSTER_ADDR="http://127.0.0.1:8201" \
      -e VAULT_API_ADDR="http://$VM_IP_ADDR:8200" \
      -v "$VAULT_PATH"/vault/config/:/vault/config \
      -v "$VAULT_PATH"/vault/data/:/vault/file:z \
      --cap-add=IPC_LOCK \
      -d \
      hashicorp/vault vault server -config=/vault/config/vault-server.hcl

  # Check if docker is running
  sleep 8
  if ! sudo docker ps | grep -q vault; then
    echo "Vault container is not running"
    exit 1
  fi
  echo "vault is running!"
}

initvault() {
    echo "Initializing Vault"
    export VAULT_ADDR="http://127.0.0.1:8200"
    vault operator init \
        -key-shares=1 \
        -key-threshold=1 > /$VAULT_PATH/vault/vault_init_output.txt

    #docker cp vault:/vault/vault_init_output.txt $VAULT_PATH/vault/vault_init_output.txt

    grep 'Unseal Key 1' "$VAULT_PATH"/vault/vault_init_output.txt \
        | awk '{print $NF}' > "$VAULT_PATH"/vault/unseal_key.txt

    grep 'Initial Root Token' "$VAULT_PATH"/vault/vault_init_output.txt \
        | awk '{print $NF}' > "$VAULT_PATH"/vault/root_token.txt

    # Check if unseal_key.txt is empty
    if [ ! -s "$VAULT_PATH"/vault/unseal_key.txt ]; then
      echo "Error: unseal_key.txt is empty or not found!"
      exit 1
    fi

    # Unseal Vault
    UNSEAL_KEY=$(cat "$VAULT_PATH"/vault/unseal_key.txt)
    echo "Unsealing Vault with key: $UNSEAL_KEY"

    vault operator unseal $UNSEAL_KEY

STATUS=$(curl http://127.0.0.1:8200/v1/sys/seal-status | jq -r '.sealed')

if [ "$STATUS" == "false" ]; then
  echo "Vault is unsealed and ready!"
  exit 1
else
  echo "Vault is sealed and not ready to use"
  exit 1
fi
}

addcacert() { # Add CA cert to Vault container (first run only)
    echo "Install The AD Self-Signed Certificate into Vault container"
    # convert cer to pem format
    openssl x509 -inform DER -in ad-cert.cer -out ad-cert.pem
    sudo docker cp /tmp/ad-cert.pem vault:/tmp/ad-cert.pem
    # Method 1: Append the certificate to the CA bundle --> Get the self-sign cert from AD first
    sudo docker exec vault sh -c 'cat /tmp/ad-cert.pem >> /etc/ssl/certs/ca-certificates.crt'

    # Verify it was added
    sudo docker exec vault tail -20 /etc/ssl/certs/ca-certificates.crt

    # Restart Vault
    sudo docker restart vault
}

setupvault
initvault
#addadcert #(If needed ldaps)

echo "VAULT_ADDR=http://$VM_IP_ADDR:8200"
echo "VAULT_TOKEN=$(cat $VAULT_PATH/vault/root_token.txt)"

