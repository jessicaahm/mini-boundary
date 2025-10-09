#!/bin/bash

# Vault environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot
export LDAP_URL=ldaps://13.218.126.189:636
export LDAP_BIND_DN="CN=vault,CN=Users,DC=example,DC=local"
export LDAP_BIND_PASSWORD="P@ssw0rd123!"
export LDAP_GRP_DN="CN=NewGroup,DC=example,DC=local"
export UPNDOMAIN="example.local"
export LDAP_USR_DN="CN=Users,DC=example,DC=local"
# To be updated for boundary setup
export AUTH_METHOD_ID="ampw_MTQCxmcbA4" 
export ORG_SCOPE_ID="o_8J6KWBIggQ"
export ADMIN_LOGIN_UID="admin"
export BOUNDARY_ADDR="http://3.239.219.75:9200/"
export BOUNDARY_PASSWORD="mypassword"
export CRED_STORE_ID="clvlt_dompUlx0HB"

vault() {
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=myroot vault vault "$@"
}

addcacert() { # Add CA cert to Vault container (first run only)
    echo "Install The AD Self-Signed Certificate into Vault container"
    # convert cer to pem format
    openssl x509 -inform DER -in ad-cert.cer -out ad-cert.pem
    docker cp /tmp/ad-cert.pem vault:/tmp/ad-cert.pem
    # Method 1: Append the certificate to the CA bundle --> Get the self-sign cert from AD first
    docker exec vault sh -c 'cat /tmp/ad-cert.pem >> /etc/ssl/certs/ca-certificates.crt'

    # Verify it was added
    docker exec vault tail -20 /etc/ssl/certs/ca-certificates.crt

    # Restart Vault
    docker restart vault
}

##### FOR TROUBLESHOOTING #####
# Verify LDAP SEARCH work
#LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD -b "DC=example,DC=local" "(objectClass=user)" cn

# Validate LDIF syntax
# LDAPTLS_REQCERT=never ldapmodify -H $LDAP_URL \
#   -D $LDAP_BIND_DN \
#   -w $LDAP_BIND_PASSWORD \
#   -f /tmp/creation.ldif \
#   -n

# Check LDAP Group
LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD \
  -b "DC=example,DC=local" \
  "(cn=NewGroup)" member

LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD \
  -b "DC=example,DC=local" \
  "(objectClass=organizationalUnit)" \
  dn
###############################

# setup ldap secret engine in vault
setupldapsecretengine(){
    echo "Logging into Vault..."
    vault login myroot

    echo "Enabling LDAP secrets engine..."
    vault secrets enable ldap

    echo "Configuring LDAP secrets engine for Active Directory..."
    vault write ldap/config \
        binddn="$LDAP_BIND_DN" \
        bindpass="$LDAP_BIND_PASSWORD" \
        url="$LDAP_URL" \
        schema=ad \
        insecure_tls=true \
        userdn="CN=Users,DC=example,DC=local"

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
    echo "  vault read ldap/creds/readonly"
}

setupldapauthengine(){
    echo "setup ldap auth engine in vault"
    vault login myroot
    # Enable auth engine
    vault auth enable ldap

    # Configure LDAP auth method
    vault write auth/ldap/config \
    url=$LDAP_URL \
    userdn=$LDAP_USR_DN \
    groupdn=$LDAP_GRP_DN \
    groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))" \
    groupattr="cn" \
    upndomain=$UPNDOMAIN \
    certificate=@/tmp/ad-cert.pem \
    insecure_tls=false \
    starttls=true

    # write policy
    cat > /tmp/policy.hcl <<'EOF'
path "*" { #please do not use this policy in production
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
    docker cp /tmp/policy.hcl vault:/tmp/policy.hcl
    vault policy write naughty /tmp/policy.hcl

    #LDAP Group Mapping
    vault write auth/ldap/groups/NewGroup policies=naughty
    #vault login -method=ldap username=v_1759983415 password=GSkh3qREm52V992j6bnd0ozEBMuLKPLRufQeOTt6K7nvLwR440igsSWIYX1gM7Bs

}

setupboundarytarget() {
    # setup boundary target to use vault ldap dynamic credential
    echo "setup boundary target to use vault ldap dynamic credential"

    #authentication to boundary
    boundary authenticate password \
        -auth-method-id=$AUTH_METHOD_ID \
        -login-name=$ADMIN_LOGIN_UID \
        -password=env://BOUNDARY_PASSWORD

    #To add in script (currently done via console)
    #1. Create project scope
    #2. Create Vault credential Store
    #3. To create target

   #create credential store
   boundary credential-libraries update vault-generic \
   -id $CRED_STORE_ID \
   -vault-http-method GET \
   -vault-path "ldap/creds/readonly" \
   -credential-mapping-override username_attribute=username \
   -credential-mapping-override password_attribute=password
}

# setupldapsecretengine
# setupldapauthengine
# setupboundarytarget
