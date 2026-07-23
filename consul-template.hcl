# consul-template reads CONSUL_HTTP_ADDR env var automatically for Consul API access.
# Approach A: no vault block needed — cert is bind-mounted from host.

template {
  source      = "/etc/consul-template/templates/haproxy.cfg.ctmpl"
  destination = "/etc/haproxy/haproxy.cfg"
  perms       = 0644
  command     = "haproxy -c -f /etc/haproxy/haproxy.cfg && kill -USR2 $(cat /var/run/haproxy/haproxy.pid) 2>/dev/null || true"
}

wait {
  min = "2s"
  max = "10s"
}

exec {
  command       = ["haproxy", "-f", "/etc/haproxy/haproxy.cfg", "-W", "-p", "/var/run/haproxy/haproxy.pid"]
  splay         = "5s"
  reload_signal = "SIGUSR2"
  kill_signal   = "SIGTERM"
  kill_timeout  = "30s"
}
