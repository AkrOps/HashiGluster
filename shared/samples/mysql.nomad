# Based on https://learn.hashicorp.com/tutorials/nomad/stateful-workloads-host-volumes?in=nomad/stateful-workloads
# The original Nomad host volume has been commented out and replaced with a Docker bind-mount into the GlusterFS
# mounted filesystem. Also moved network resource to group network block, as the former has been deprecated.

job "mysql-server" {
  datacenters = ["dc1"]
  type        = "service"

  group "mysql-server" {
    count = 1

    // volume "mysql" {
    //   type      = "host"
    //   read_only = false
    //   source    = "mysql"
    // }

    // https://www.nomadproject.io/docs/job-specification/network
    network {
      port "db" {
        static = 3306
      }
    }

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    // https://www.nomadproject.io/docs/job-specification/task
    task "mysql-server" {
      // https://www.nomadproject.io/docs/drivers/docker
      driver = "docker"

      // volume_mount {
      //   volume      = "mysql"
      //   destination = "/var/lib/mysql"
      //   read_only   = false
      // }

      env = {
        "MYSQL_ROOT_PASSWORD" = "password"
      }

      config {
        image = "hashicorp/mysql-portworx-demo:latest"

        volumes = [ "/mnt/gluster/volumes/mysql-test:/var/lib/mysql" ]

        ports = [ "db" ]
      }

      resources {
        cpu    = 500
        # Original value, a little bit abusive for a test t3.micro
        # memory = 1024
        # probably not suitable for prod ;)
        memory = 512
      }

      service {
        name = "mysql-server"
        port = "db"

        check {
          type     = "tcp"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }
  }
}
