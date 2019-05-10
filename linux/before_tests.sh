#!/bin/bash
# Linux Foundation currently does not support trusting self-signed certificates,
# so as a workaround to allow the tests to pass, we will add our test server
# certificate to the system's trusted list.
echo "Adding self-signed test certificate to trusted certificates"
cat TestServer/Credentials/cert.pem >> /etc/ssl/certs/ca-certificates.crt
