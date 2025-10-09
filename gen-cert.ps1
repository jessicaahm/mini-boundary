New-SelfSignedCertificate `
    -Subject "CN=example.local" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyExportPolicy Exportable `
    -Provider "Microsoft RSA SChannel Cryptographic Provider" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -TextExtension @("2.5.29.17={text}DNS=example.local&DNS=EC2AMAZ-0CS0CUJ&DNS=EC2AMAZ-0CS0CUJ.example.local&DNS=*.example.local&DNS=localhost&IPAddress=13.218.126.189&IPAddress=127.0.0.1&IPAddress=10.0.1.185") `
    -NotAfter (Get-Date).AddYears(5)

# Also need to follow --> https://www.dell.com/support/kbdoc/en-eg/000213104/how-to-configure-ldaps-for-active-directory-integration

# Thumbprint                                Subject
# ----------                                -------
# FF57FBA1A02209B8F6FD500D26CB3136684B3E69  CN=example.local