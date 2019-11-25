vault {
  renew_token = false
  vault_agent_token_file = "/home/vault/.vault-token"
  retry {
    backoff = "1s"
  }
}

template {
  destination = "/etc/secrets/myapp"
  contents = <<EOH
  {{- with secret "kv/myapp" }}
username: {{ .Data.username }}
password: {{ .Data.password }}
  {{ end }}
  EOH
}
