# Test-only TLS fixtures

**These keys are TEST-ONLY.** They are committed on purpose, protect nothing,
and must never be used outside this test suite.

- `ca.pem` / `ca_key.pem` — self-signed test CA (Certificate Authority)
- `localhost.pem` / `localhost_key.pem` — leaf certificate signed by that CA,
  with subjectAltName covering `DNS:localhost` and `IP:127.0.0.1`, valid 10 years

`Arangox.ProtocolServer` serves `localhost.pem` in TLS mode; clients verify
against `ca.pem`. The pre-existing `test/cert.pem` is unrelated — it remains
the negative fixture (a certificate no CA here has signed).

## Regeneration commands

Run from this directory:

```sh
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout ca_key.pem -out ca.pem \
  -subj "/CN=Arangox Test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout localhost_key.pem -out localhost.csr \
  -subj "/CN=localhost"

openssl x509 -req -sha256 -days 3650 \
  -in localhost.csr -CA ca.pem -CAkey ca_key.pem -CAcreateserial \
  -out localhost.pem \
  -extfile /dev/stdin <<'EOF'
subjectAltName = DNS:localhost, IP:127.0.0.1
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

rm localhost.csr ca.srl
```
