log_level = "INFO"
server = true
data_dir = "/opt/consul/data"
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
advertise_addr = "IP_ADDRESS"
bootstrap_expect = SERVER_COUNT
ui_config {
  enabled = true
}

service {
  name = "consul"
}

retry_join = ["RETRY_JOIN"]

// acl {
//   enabled = true
//   default_policy = "deny"
//   down_policy = "extend-cache"
// }
