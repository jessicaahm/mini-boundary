New-SelfSignedCertificate `
    -Subject "CN=lab.com" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyExportPolicy Exportable `
    -Provider "Microsoft RSA SChannel Cryptographic Provider" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -TextExtension @("2.5.29.17={text}DNS=lab.com&DNS=EC2AMAZ-0CS0CUJ&DNS=EC2AMAZ-0CS0CUJ.lab.com&DNS=*.lab.com&DNS=localhost&IPAddress=3.238.4.183&IPAddress=127.0.0.1&IPAddress=10.0.1.127") `
    -NotAfter (Get-Date).AddYears(5)

# Also need to follow --> https://www.dell.com/support/kbdoc/en-eg/000213104/how-to-configure-ldaps-for-active-directory-integration

# Thumbprint                                Subject
# ----------                                -------
# FF57FBA1A02209B8F6FD500D26CB3136684B3E69  CN=example.local

# openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 \
#   -nodes -keyout server.key -out server.crt \
#   -subj "/CN=lab.com" \
#   -addext "subjectAltName=DNS:lab.com,DNS:*.lab.com,IP:192.168.10.7,IP:127.0.0.1"
#   ldap://192.168.10.7:389