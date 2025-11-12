#!/bin/bash

export VAULT_ADDR=http://3.239.158.79:8200
export VAULT_TOKEN="hvs.cmKKzJz4heI6yBoe8w7qs0mI"

export TARGET_VM="44.203.31.9"

export current_file_path=$(pwd)

vault secrets enable -path=ssh ssh

# 1. Configure vault with a CA for signing client keys
vault write ssh/config/ca generate_signing_key=true -format=json
vault read -field=public_key ssh/config/ca > trusted-user-ca-keys.pem

# 2. Copy file to target VM. Note: This should be done by automation/orchestrator
scp -i "boundary.pem" "${current_file_path}/trusted-user-ca-keys.pem" ubuntu@${TARGET_VM}:/home/ubuntu/trusted-user-ca-keys.pem
# vault read -field=public_key ssh/config/ca
echo "TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh

# 3. Create a Vault role for signing client keys
# Role 1: Admin [Excessive privilege]
# Role 2: User

vault write ssh/roles/admin -<<"EOH"
{
  "algorithm_signer": "rsa-sha2-256",
  "allow_user_certificates": true,
  "allowed_users": "*",
  "allowed_extensions": "permit-pty,permit-port-forwarding",
  "default_extensions": {
    "permit-pty": ""
  },
  "key_type": "ca",
  "default_user": "ubuntu",
  "ttl": "30m0s"
}
EOH

vault write ssh/roles/user -<<"EOH"
{
  "algorithm_signer": "rsa-sha2-256",
  "allow_user_certificates": true,
  "allowed_users": "*",
  "allowed_extensions": "permit-pty,permit-port-forwarding",
  "default_extensions": {
    "permit-pty": ""
  },
  "key_type": "ca",
  "default_user": "ubuntu",
  "ttl": "3m0s"
}
EOH

# Requestor: 
cd ./requestor
ssh-keygen -t rsa -C "user@example.com"
export current_file_path=$(pwd)
vault write -field=signed_key ssh/sign/user \
    public_key=@${current_file_path}/user.pub > user-signed-cert.pub

chmod 400 user-signed-cert.pub
chmod 400 user
ssh -i user ubuntu@${TARGET_VM}

ssh -i user-cert.pub -i user ubuntu@44.203.31.9