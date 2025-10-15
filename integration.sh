#!/bin/bash
# BOUNDARY CLI is needed
# Pass is needed

# Set up Vault Creds Store
export AUTH_METHOD_ID="ampw_itLVtDbjHJ"
export ADMIN_LOGIN_UID="admin"
export BOUNDARY_PASSWORD="mypassword"
export BOUNDARY_VM_IP_ADDR="44.201.45.112"
export VAULT_VM_IP_ADDR="44.198.55.208"
export PROJECT_SCOPE="p_C36VKbloaD"
export VAULT_ADDR="http://$VAULT_VM_IP_ADDR:8200"
export VAULT_TOKEN="hvs.GyvuuXlNWOmjnw934sKwY0hT" 
export VAULT_CREDS_TOKEN=""
export BOUNDARY_ADDR="http://$BOUNDARY_VM_IP_ADDR:9200"
# Set up Secret Engine
export LDAP_URL="ldaps://10.0.1.185:636" 
 # need be created in AD first
export LDAP_BIND_DN="CN=vault,CN=Users,DC=example,DC=local"
export LDAP_BIND_PASSWORD='P@ssw0rd123!' 
# need to be updated based on your AD structure
export LDAP_USER_DN="CN=Users,DC=example,DC=local"
export LDAP_GRP_DN="CN=NewGroup,DC=example,DC=local"
export UPNDOMAIN="example.local"
export LDAP_USR_DN="CN=Users,DC=example,DC=local"

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

path "ldap/creds/readonly" {
  capabilities = ["update","read","list"]
}


EOF

vault policy write boundary-controller boundary-controller-policy.hcl

echo "Create token for integration"
VAULT_CREDS_TOKEN=$(vault token create -period=30m -orphan -policy=boundary-controller -renewable=true -orphan=true -format=json | jq -r '.auth.client_token')
echo "Token: $VAULT_CREDS_TOKEN"
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
    CRED_STORE_ID=$(boundary credential-stores create vault -scope-id $PROJECT_SCOPE \
        -vault-address $VAULT_ADDR \
        -vault-token $VAULT_CREDS_TOKEN \
        -format json | jq -r '.item.id')

    echo "Credential Store ID: $CRED_STORE_ID"

    #2. Create credential library
    CRED_LIB_ID=$(boundary credential-libraries create vault-generic \
        -credential-store-id $CRED_STORE_ID \
        -vault-path "ldap/creds/readonly" \
        -vault-http-method "GET" \
        -credential-type "username_password" \
        -credential-mapping-override username_attribute=username \
        -credential-mapping-override password_attribute=password \
        -format json | jq -r '.item.id')

    echo "Credential Library ID: $CRED_LIB_ID"
}

# setup ldap secret engine in vault
setupldapsecretengine(){
    echo "Logging into Vault..."

    echo "Enabling LDAP secrets engine..."
    vault secrets enable ldap

    echo "Configuring LDAP secrets engine for Active Directory..."
    vault write ldap/config \
        binddn="$LDAP_BIND_DN" \
        bindpass="$LDAP_BIND_PASSWORD" \
        url="$LDAP_URL" \
        schema=ad \
        insecure_tls=true \
        userdn="$LDAP_USER_DN"

    echo "LDAP secrets engine configured successfully!"

    echo ""
    echo "Creating dynamic role for read-only users..."

    # Create LDIF file for user creation (simpler approach)
    cat > /tmp/creation.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
userPrincipalName: {{.Username}}@example.local
sAMAccountName: {{.Username}}

dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: modify
replace: unicodePwd
unicodePwd::{{ printf "%q" .Password | utf16le | base64 }}
-
replace: userAccountControl
userAccountControl: 66048
-

dn: CN=NewGroup,DC=example,DC=local
changetype: modify
add: member
member: CN={{.Username}},CN=Users,DC=example,DC=local
-
EOF


    # Create LDIF file for rollback (disable account instead of delete)
# Create LDIF file for rollback (disable account instead of delete) - FIXED
cat > /tmp/rollback.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: modify
replace: userAccountControl
userAccountControl: 514
-
EOF
    # Create LDIF file for user deletion
    cat > /tmp/deletion.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: delete
EOF

    # Copy LDIF files to Vault container
    docker cp /tmp/creation.ldif vault:/tmp/creation.ldif
    #docker cp /tmp/rollback.ldif vault:/tmp/rollback.ldif
    docker cp /tmp/deletion.ldif vault:/tmp/deletion.ldif

    # Create the dynamic role
    #docker cp /tmp/creation.ldif vault:/tmp/creation.ldif

    vault write ldap/role/readonly \
        creation_ldif=@/tmp/creation.ldif \
        deletion_ldif=@/tmp/deletion.ldif \
        default_ttl=1h \
        max_ttl=24h \
        username_template="v_{{unix_time}}"

    vault read ldap/creds/readonly

    echo ""
    echo "Dynamic secrets engine configured!"
    echo ""
    echo "Test dynamic credential generation:"
    echo "vault read ldap/creds/readonly"
}

setupldapauthengine(){
    echo "setup ldap auth engine in vault"
    # Enable auth engine
    vault auth enable ldap

    # Configure LDAP auth method
    vault write auth/ldap/config \
    url=$LDAP_URL \
    userdn=$LDAP_USR_DN \
    groupdn=$LDAP_GRP_DN \
    groupfilter='(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))' \
    groupattr='cn' \
    upndomain=$UPNDOMAIN \
    certificate=@/tmp/ad-cert.pem \
    insecure_tls=false \
    starttls=true

    # write policy
    cat > privilege-policy.hcl <<'EOF'
path "*" { #please do not use this policy in production
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
    vault policy write naughty privilege-policy.hcl

    #LDAP Group Mapping
    vault write auth/ldap/groups/NewGroup policies=naughty
    # Test login
    vault read ldap/creds/readonly -format=json > LDAP_USER.json
    export LDAP_USER_USERNAME=$(jq -r '.data.username' LDAP_USER.json)
    export LDAP_USER_PASSWORD=$(jq -r '.data.password' LDAP_USER.json)
    vault login -method=ldap username=$LDAP_USER_USERNAME password=$LDAP_USER_PASSWORD
}

setuptarget() {
    echo "create target for boundary to access"

}

#setupldapsecretengine
#setupldapauthengine
setupvaultcredstore
