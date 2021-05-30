job "nginx" {
  datacenters = ["dc1"]

  group "nginx" {
    count = 2

    network {
      port "http" {
        static = 80
      }
    }

    service {
      name = "nginx"
      port = "http"
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx"

        ports = ["http"]

        volumes = [
          "new:/etc/nginx/conf.d",
        ]
      }

      artifact {
        source = "https://gist.githubusercontent.com/JBeCast/270b9e577f6274932c7e6780225da679/raw/377ff4eab87a1b681876dfda4722507f9171a1e1/nginx.conf"
      }

      template {
        source        = "local/nginx.conf"
        destination   = "new/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
    }
  }
}

