#!/bin/bash

# Vault environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

vault() {
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=myroot vault vault "$@"
}

addcacert() {
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


# LDAP Variables - Using LDAPS due to Windows Server 2025 security requirements
export LDAP_URL=ldaps://13.218.126.189:636
export LDAP_BIND_DN="CN=vault,CN=Users,DC=example,DC=local"
export LDAP_BIND_PASSWORD="P@ssw0rd123!"

echo "Testing LDAP connection first..."


# Verify LDAP SEARCH work
LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD -b "DC=example,DC=local" "(objectClass=user)" cn

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


# Validate LDIF syntax
LDAPTLS_REQCERT=never ldapmodify -H $LDAP_URL \
  -D $LDAP_BIND_DN \
  -w $LDAP_BIND_PASSWORD \
  -f /tmp/creation.ldif \
  -n
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
unicodePwd::{{.Password | utf16le | base64}}
-
replace: userAccountControl
userAccountControl: 512

dn: CN=test-group,CN=Users,DC=example,DC=local
changetype: modify
add: member
member: CN={{.Username}},CN=Users,DC=example,DC=local
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
    docker cp /tmp/rollback.ldif vault:/tmp/rollback.ldif
    docker cp /tmp/deletion.ldif vault:/tmp/deletion.ldif

    # Create the dynamic role
    vault write ldap/role/readonly \
        creation_ldif=@/tmp/creation.ldif \
        deletion_ldif=@/tmp/deletion.ldif \
        default_ttl=1h \
        max_ttl=24h \
        username_template="v_{{unix_time}}"

    # Clean up temp files
    rm -f /tmp/creation.ldif /tmp/deletion.ldif

    echo ""
    echo "Dynamic secrets engine configured!"
    echo ""
    echo "Test dynamic credential generation:"
    echo "  vault read ldap/creds/readonly"
}

setupldapsecretengine

