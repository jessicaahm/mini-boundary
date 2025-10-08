New-SelfSignedCertificate `
    -Subject "CN=example.local" `
    -DnsName "example.local", "EC2AMAZ-0CS0CUJ", "EC2AMAZ-0CS0CUJ.example.local", "*.example.local" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyExportPolicy Exportable `
    -Provider "Microsoft RSA SChannel Cryptographic Provider" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -TextExtension @("2.5.29.17={text}DNS=example.local&DNS=EC2AMAZ-0CS0CUJ.example.local&DNS=localhost&IPAddress=13.222.94.228&IPAddress=127.0.0.1") 
    -NotAfter (Get-Date).AddYears(5)

# Also need to follow --> https://www.dell.com/support/kbdoc/en-eg/000213104/how-to-configure-ldaps-for-active-directory-integration