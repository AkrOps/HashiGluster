log_level = "INFO"
server = true
data_dir = "/opt/consul/data"
bind_addr = "IP_ADDRESS"
client_addr = "IP_ADDRESS"
advertise_addr = "IP_ADDRESS"
bootstrap_expect = SERVER_COUNT
ui = true

service {
  name = "consul"
}

retry_join = ["RETRY_JOIN"]

// acl {
//   enabled = true
//   default_policy = "deny"
//   down_policy = "extend-cache"
// }
