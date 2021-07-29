verify_incoming = true,
verify_outgoing = true,
verify_server_hostname = true,
ca_file = "/opt/consul/data/certs/consul-agent-ca.pem",
cert_file = "/opt/consul/data/certs/dc1-server-consul-HOST_NUMBER.pem",
key_file = "/opt/consul/data/certs/dc1-server-consul-HOST_NUMBER-key.pem",
auto_encrypt {
  allow_tls = true
}
