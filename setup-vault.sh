#!/bin/bash
# Vault LDAP Secret Secret Engine
export LDAP_URL=ldaps://10.0.1.127:636 # AD Server IP
export LDAP_BIND_DN="CN=vault,CN=Users,DC=lab,DC=com"
export LDAP_BIND_PASSWORD='P@ssw0rd123!'
export LDAP_USER_DN="CN=Users,DC=lab,DC=com"
export LDAP_GRP_DN="CN=NewGroup,DC=lab,DC=com"
export UPNDOMAIN="lab.com"
export LDAP_USR_DN="CN=Users,DC=lab,DC=com"
# To be updated for boundary setup
export AUTH_METHOD_ID="ampw_itLVtDbjHJ" 
export SCOPE_ID="o_32uhtsgOm5"
export PROJ_SCOPE="p_C36VKbloaD"
export ADMIN_LOGIN_UID="admin"
export BOUNDARY_ADDR="http://3.239.219.75:9200/"
export BOUNDARY_PASSWORD="mypassword"
export BOUNDARY_TLS_INSECURE=true
# export CRED_STORE_ID="clvlt_dompUlx0HB"

addcacert() { # Add CA cert to Vault container (first run only)
    echo "Install The AD Self-Signed Certificate into Vault container"
    scp -i "boundary.pem" /Users/jessica.ang/Library/CloudStorage/OneDrive-IBM/GitHub/demo/boundary/mini-boundary/SSL/ad-cert.cer ubuntu@3.208.87.161:/tmp/ad-cert.cer
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

##### FOR TROUBLESHOOTING #####
# Verify LDAP SEARCH work
#LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD -b "DC=lab,DC=com" "(objectClass=user)" dn

# Validate LDIF syntax
# LDAPTLS_REQCERT=never ldapmodify -H $LDAP_URL \
#   -D $LDAP_BIND_DN \
#   -w $LDAP_BIND_PASSWORD \
#   -f /tmp/creation.ldif \
#   -n

# Check LDAP Group
# LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD \
#   -b "DC=example,DC=local" \
#   "(cn=NewGroup)" member

# LDAPTLS_REQCERT=never ldapsearch -x -H $LDAP_URL -D $LDAP_BIND_DN -w $LDAP_BIND_PASSWORD \
#   -b "DC=example,DC=local" \
#   "(objectClass=organizationalUnit)" \
#   dn
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


setuprecording() {
    echo "setup session recording store"
    # Setup MinIO S3-Compatible server
    mc alias set myminio http://localhost:9000 minioadmin minioadmin123

    # Create user
    mc admin user add myminio boundary $BOUNDARY_PASSWORD
    mc admin user list myminio

    # Step 1: Create MinIO Access Keys
    OUTPUT=$(mc admin user svcacct add myminio minioadmin --json)
    echo "$OUTPUT"
    # ACCESS_KEY=$(echo "$OUTPUT" | jq -r '.accessKey')
    # SECRET_KEY=$(echo "$OUTPUT" | jq -r '.secretKey')

#  "status": "success",
#  "accessKey": "9ULVDQVNTAWAD1I8LW2I",
#  "secretKey": "SDNyyQ81Ee7+uOQp0N3tPQoSPuv+pkzxhgnb70Fl",
#  "accountStatus": "enabled",
#  "expiration": "1970-01-01T00:00:00Z"
# }')

    export ACCESS_KEY="1WRHOAAD7WH7U1PO89RS"
    export SECRET_KEY="6TInONmfHBA0T+pebGhmLrVKKmy1ahDWt4BsD0w1"

    {
 "status": "success",
 "accessKey": "1WRHOAAD7WH7U1PO89RS",
 "secretKey": "6TInONmfHBA0T+pebGhmLrVKKmy1ahDWt4BsD0w1",
 "accountStatus": "enabled",
 "expiration": "1970-01-01T00:00:00Z"
}

    # Attach policy
    mc admin policy attach myminio readwrite --user boundary

    # Step 2: Create a new bucket named "boundary-recordings"
    mc mb minioadmin/boundary-recordings

    # Test the new user
    mc alias set test-boundary http://localhost:9000 $ACCESS_KEY $SECRET_KEY
    
    #mc ls test-boundary
    #mc alias remove test-boundary

    export BOUNDARY_TOKEN=$(boundary authenticate password \
        -auth-method-id="$AUTH_METHOD_ID" \
        -login-name=$ADMIN_LOGIN_UID \
        -password=env://BOUNDARY_PASSWORD \
        -format json | jq  -r '.item.attributes.token')

    boundary storage-buckets create \
   -bucket-name myminiobucket \
   -plugin-name minio \
   -scope-id global\
   -bucket-prefix="boundary/boundary-recordings" \
   -worker-filter '"local" in "/tags/worker"' \
   -attr endpoint_url="http://127.0.0.1:9000" \
   -attr disable_credential_rotation=true \
   -secret access_key_id=$ACCESS_KEY \
   -secret secret_access_key=$SECRET_KEY \
   -token env://BOUNDARY_TOKEN
    
}

setupvault
# setupvaultcredstore
# addcacert
# setupldapsecretengine
# setupldapauthengine
# setupvaultcredstore
# setuprecording

