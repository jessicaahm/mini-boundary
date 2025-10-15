#!/bin/bash
# BOUNDARY CLI is needed
# Pass is needed

# Set up Vault Creds Store
export AUTH_METHOD_ID="ampw_K4vJNwHzr1"
export ADMIN_LOGIN_UID="admin"
export BOUNDARY_PASSWORD="mypassword"
export BOUNDARY_VM_IP_ADDR="44.201.45.112"
export VAULT_VM_IP_ADDR="44.198.55.208"
export PROJECT_SCOPE="p_jUtM5RkX8o"
export VAULT_ADDR="http://$VAULT_VM_IP_ADDR:8200"
export VAULT_TOKEN="hvs.GyvuuXlNWOmjnw934sKwY0hT" 
export BOUNDARY_ADDR="http://$BOUNDARY_VM_IP_ADDR:9200"

setuptoken() {
    # Create token for integration: Periodic + Renewable + Orphan
    cat > boundary-controller-policy.hcl <<EOF
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
EOF

vault policy write boundary-controller boundary-controller-policy.hcl

echo "Create token for integration"
VAULT_TOKEN=$(vault token create -period=30m -orphan -policy=boundary-controller -renewable=true -orphan=true -format=json | jq -r '.auth.client_token')
echo "Token: $VAULT_TOKEN"
}

setupvaultcredstore() {
    # setup boundary target to use vault ldap dynamic credential
    echo "Setup Vault Credential Store in Boundary"

    #authentication to boundary
    boundary authenticate password \
        -auth-method-id="$AUTH_METHOD_ID" \
        -login-name="$ADMIN_LOGIN_UID" \
        -password=env://BOUNDARY_PASSWORD

    #1. Create Vault Credential Store
    setuptoken
    boundary credential-stores create vault -scope-id $PROJECT_SCOPE \
        -vault-address $VAULT_ADDR \
        -vault-token $VAULT_TOKEN 

    #2. Create Vault credential Store
    #3. To create target

   #create credential store
#    boundary credential-libraries update vault-generic \
#    -id $CRED_STORE_ID \
#    -vault-http-method GET \
#    -vault-path "ldap/creds/readonly" \
#    -credential-mapping-override username_attribute=username \
#    -credential-mapping-override password_attribute=password
}

setupvaultcredstore