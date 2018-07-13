locals {
  CLOUD_INIT_CONFIG = <<EOF
#cloud-config

write_files:
- path: /etc/systemd/system/wordpress.service.d/environment.conf
  permissions: 0644
  owner: root
  content: |
    [Service]
    Environment=WORDPRESS_DB_HOST=db:3306
    Environment=WORDPRESS_DB_USER=wordpress
    Environment=WORDPRESS_DB_PASSWORD=${var.WORDPRESS_DB_PASSWORD}
- path: /etc/systemd/system/wordpress.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Description=Start a wordpress docker container
    After=db.service
    Requires=docker.service

    [Service]
    Type=simple
    Restart=always
    ExecStartPre=-/usr/bin/docke stot wordpress
    ExecStartPre=-/usr/bin/docker rm -v wordpress
    ExecStart=/usr/bin/docker run --net wordpress_network --name=wordpress -e WORDPRESS_DB_HOST="$${WORDPRESS_DB_HOST}" -e WORDPRESS_DB_USER="$${WORDPRESS_DB_USER}" -e WORDPRESS_DB_PASSWORD="$${WORDPRESS_DB_PASSWORD}" --log-driver=gcplogs wordpress:latest

- path: /etc/systemd/system/db.service.d/environment.conf
  permissions: 0644
  owner: root
  content: |
    [Service]
    Environment=MYSQL_ROOT_PASSWORD=${var.ROOT_DB_PASSWORD}
    Environment=MYSQL_DATABASE=wordpress
    Environment=MYSQL_USER=wordpress
    Environment=MYSQL_PASSWORD=${var.WORDPRESS_DB_PASSWORD}
- path: /etc/systemd/system/db.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Description=Start a mysql docker container
    Requires=docker.service

    [Service]
    Type=simple
    Restart=always
    ExecStartPre=-/usr/bin/docke stot db
    ExecStartPre=-/usr/bin/docker rm -v db
    ExecStart=/usr/bin/docker run --net wordpress_network --name=db -e MYSQL_ROOT_PASSWORD="$${MYSQL_ROOT_PASSWORD}" -e MYSQL_DATABASE="$${MYSQL_DATABASE}" -e MYSQL_USER="$${MYSQL_USER}" -e MYSQL_PASSWORD="$${MYSQL_PASSWORD}" -v /mnt/disks/wordpress-db/mysql:/var/lib/mysql --log-driver=gcplogs mysql:5.7
- path: /etc/systemd/system/portal.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Description=Start a https-portal docker container
    After=wordpress.service
    Requires=docker.service

    [Service]
    Type=simple
    Restart=always
    ExecStartPre=-/usr/bin/docke stot https-portal
    ExecStartPre=-/usr/bin/docker rm -v https-portal
    ExecStart=/usr/bin/docker run --net wordpress_network -p 443:443 -p 80:80 --name=https-portal -e DOMAINS="blog.uu4k.me -> http://wordpress" -e STAGE="production" --log-driver=gcplogs -v /var/https-portal/:/var/lib/https-portal/ steveltn/https-portal:1.3
- path: /var/startup.sh
  permissions: 0744
  owner: root
  content: |
    mkdir -p /mnt/disks/wordpress-db
    mount -o discard,defaults /dev/sdb /mnt/disks/wordpress-db

    if [ $? != 0 ]; then
        mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb 
        mount -o discard,defaults /dev/sdb /mnt/disks/wordpress-db
    fi

    mkdir -p /var/https-portal
runcmd:
- sh /var/startup.sh
- docker network create wordpress_network
- systemctl daemon-reload
- systemctl start db.service
- systemctl start wordpress.service
- systemctl start portal.service
EOF
}
