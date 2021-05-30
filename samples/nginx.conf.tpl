upstream backend {
{{ range service "demo-webapp" }}
  server {{ .Address }}:{{ .Port }};
{{ else }}server 127.0.0.1:65535; # force a 502
{{ end }}
}

server {
   server_name nomad-nginx-test.avadigi.de;
   listen 80;

   location / {
      proxy_pass http://backend;
   }
}

