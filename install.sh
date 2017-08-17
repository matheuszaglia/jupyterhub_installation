myuser=$USER
mkdir ~/jupyterhub
cd ~/jupyterhub
wget --no-check-certificate https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh

bash Miniconda3-latest-Linux-x86_64.sh

sudo apt install npm nodejs-legacy

sudo npm install -g configurable-http-proxy

conda install traitlets tornado jinja2 sqlalchemy 

pip install jupyterhub

sudo apt install nginx

sudo mkdir /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt


sudo -E sh -c 'cat > /etc/nginx/nginx.conf << EOF
user www-data;
worker_processes 4;
pid /run/nginx.pid;

events {
  worker_connections 1024;
}

http {

        include /etc/nginx/mime.types;
        default_type application/octet-stream;

    server {
        listen 80;
        server_name jupyterhub;
        return 301 https://\$host\$request_uri?;

    }

    server {
        listen 443;
        client_max_body_size 50M;

        server_name jupyterhub;

        ssl on;
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;

        ssl_ciphers "AES128+EECDH:AES128+EDH";
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains";
        add_header X-Content-Type-Options nosniff;
        ssl_stapling on; # Requires nginx >= 1.3.7
        ssl_stapling_verify on; # Requires nginx => 1.3.7
        resolver_timeout 5s;

        # Expose logs to "docker logs".
        # See https://github.com/nginxinc/docker-nginx/blob/master/Dockerfile#L12-L14
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        #location ~ /(user-[a-zA-Z0-9]*)/static(.*) {
        #    alias /usr/local/lib/python3.4/dist-packages/notebook/static/\$2;
        #}

        location / {
            proxy_pass https://localhost:8000;

            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

            proxy_set_header X-NginX-Proxy true;
        }

        location ~* /(user/[^/]*)/(api/kernels/[^/]+/channels|terminals/websocket)/? {
            proxy_pass http://localhost:8000;

            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

            proxy_set_header X-NginX-Proxy true;

            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;

        }
    }

}
EOF'

sudo systemctl restart nginx

sudo apt update
sudo apt install apt-transport-https ca-certificates curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt update
sudo apt install docker-ce
sudo usermod -aG docker jupyterhub

pip install dockerspawner

sudo docker pull jupyterhub/systemuser

conda install ipython jupyter

touch /home/$myuser/jupyterhub/jupyterhub_config.py
cat > /home/$myuser/jupyterhub/jupyterhub_config.py << EOF
c.JupyterHub.ssl_cert = '/etc/nginx/ssl/nginx.crt'
c.JupyterHub.ssl_key = '/etc/nginx/ssl/nginx.key'
c.JupyterHub.extra_log_file = '/var/log/jupyterhub.log'

c.Authenticator.admin_users = {'jupyterhub'}

c.JupyterHub.proxy_api_ip = '0.0.0.0'
from jupyter_client.localinterfaces import public_ips
c.JupyterHub.hub_ip = public_ips()[0]

c.JupyterHub.spawner_class = 'dockerspawner.SystemUserSpawner'
c.DockerSpawner.container_image = 'jupyterhub/systemuser'
c.DockerSpawner.remove_containers = True
EOF


myuser=$USER sudo -E sh -c '
cat > /etc/systemd/system/jupyterhub.service <<EOF
[Unit]
Description=Jupyterhub
After=syslog.target network.target

[Service]
User=root
Environment="PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/home/$myuser/bin"
ExecStart=/home/$myuser/miniconda3/bin/jupyterhub -f /home/$myuser/jupyterhub_config.py

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl daemon-reload
sudo systemctl start jupyterhub
sudo systemctl enable jupyterhub
