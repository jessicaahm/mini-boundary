# Welcome to demo

Vault:

- Vault Address: http://44.200.252.234:8200/ui/
- Root Token: hvs.cmKKzJz4heI6yBoe8w7qs0mI

Boundary:

- Boundary Address: http://3.83.21.218:9200/
- admin/mypassword

```sh {"terminalRows":"7"}
vault read ssh/roles/user
```

### Issue a certificate

```sh
vault write -format=json ssh/issue/user -<<EOF > /tmp/demo/user.json
    {
    "ttl": "30m",
    "valid_principals": "ubuntu",
    "cert_type": "user",
    "extensions": {
        "permit-pty": "",
        "permit-port-forwarding": ""
    }
    }
EOF

jq -r '.data.signed_key' /tmp/demo/user.json | tr -d '\n' > /tmp/demo/id_rsa-issue-cert.pub
jq -r '.data.private_key' /tmp/demo/user.json > /tmp/demo/id_rsa-issue

chmod 600 /tmp/demo/id_rsa-issue
chmod 600 /tmp/demo/id_rsa-issue-cert.pub
```

```sh
ssh-keygen -L -f /tmp/demo/signed-cert-issue.pub
```

```sh {"terminalRows":"25"}
ssh -vvv -i /tmp/demo/id_rsa-issue-cert.pub -i /tmp/demo/id_rsa-issue ubuntu@$TARGET
```

### Generate a certificate

```sh
export VAULT_ADDR='http://44.200.252.234:8200'
export VAULT_TOKEN='hvs.cmKKzJz4heI6yBoe8w7qs0mI'
export TARGET="98.92.160.25"
```

```sh
cd /tmp
ssh-keygen -t rsa -C "user@example.com" -f /tmp/demo/id_rsa
```

```sh
vault secrets list
```

```sh {"terminalRows":"13"}
vault write -field=signed_key ssh/sign/user -<<"EOH" > /tmp/demo/signed-cert.pub
{
  "public_key": "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCYNG7RDLf6xASDJf6zKp+HaoJr3w73+Sej7IFMPHQcym7wqhlYipA8UCwpdJOSTcp2BzOsWgLMODs3wnbyoun6VIMfM+48fEWXbuBYLtwvMgo92gwrPRqN+9vsaHCIQyqgJfH+b24KJuBy3l64BODh5fq4W/pK08gpIdr6XhdtAAtKqxgob0Re0fr26q2f0MR4cxIC/N2zFCPDr3d+csf5gULJvxZFjlgvvzdNtCT6NgRy2Mj50fg7CSWtURqCKROmCfB6ZXn5DRKP+/IFrwIi9XsWAYf6GAqPTpC69WsKO+DeK07JNTe+BWMUIu9B+R0vZSdcxlpybOsHxtY/p29AP7qxemOb+w5CJzFLdYdNmbrkEK24vHTSARdDGe86Ty84sn+YDfFodKCgUWVT7tTybmu/AmrvaOJxkBTcVaUsSPLjQVh66sHeUrEeH9MlS8ZvWGHoBNGwiekEYvp5SOYqqaKNUnAWpcbgjMupLpAfKhuPr2j1+7B9N4Aiew6FnQM= user@example.com",
  "extensions": {
    "permit-pty": "",
    "permit-port-forwarding": ""
  }
}
EOH
```

```sh
ssh -i /tmp/demo/signed-cert.pub -i /tmp/demo/id_rsa ubuntu@$TARGET
```

### Details

```sh
ssh-keygen -L -f /tmp/demo/signed-cert-issue.pub
```

```sh
# tail for logs
sudo tail -f /var/log/auth.log

```