provider=""
curl -m 3 169.254.169.254/latest/meta-data/ 2>/dev/null && provider=aws || true
