!#/bin/bash

##############################################
# Install Cloudflare Tunnel
##############################################
# Add the cloudflared to the same network as Coolify
echo "Creating Docker Compose file for cloudflared..."
cat >/tmp/docker-compose.yml <<"EOF"
version: '3'
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: always
    container_name: cloudflared
    command: tunnel run --token ${tunnel_token}
    networks: 
      - coolify

networks:
  coolify:
    external: true
EOF
echo "Starting Cloudflared tunnel..."
cd /tmp
sudo docker compose up -d

# From this point on, ssh access is available via the Cloudflare tunnel

echo "Script completed."
