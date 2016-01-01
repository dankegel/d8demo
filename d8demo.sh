#!/bin/sh
# drupal 8 notes
set -e
set -x
cmd=$1

sitedomain=kegel.com
sitename=d8demo

# Don't use this password if your MySQL server is on the public internet
sqlrootpw="foobar7"

# Return IP address, or nonzero status if none
get_ip() {
    ip=`sudo lxc-ls -f | awk "/$sitename/"' {print $3}'`
    case $ip in
    [0-9]*) echo $ip; return 0;;
    *) return 1;;
    esac
}

do_create() {
    # We want to do ssh-copy-id later, so make sure there's an id
    if ! test -f ~/.ssh/id_rsa.pub && ! test -f ~/.ssh/id_dsa.pub
    then
       ssh-keygen
    fi
   
    echo "Creating LXC container named $sitename, and creating user $LOGNAME inside it"
    sudo lxc-create -t download -n $sitename -- --dist ubuntu --release wily --arch amd64
    # Create a user, add him to sudo group, install ssh
    sudo chroot /var/lib/lxc/$sitename/rootfs adduser $LOGNAME
    sudo chroot /var/lib/lxc/$sitename/rootfs sed -i "/sudo/s/\$/,$LOGNAME/;s/:,/:/" /etc/group
    sudo chroot /var/lib/lxc/$sitename/rootfs apt-get install -y openssh-server
    # Start it and add it to /etc/hosts
    sudo lxc-start -n $sitename
    while ! get_ip
    do
        sleep 1
    done
    siteip=`get_ip`
    # Remove old entry, if any
    sudo sed -i "/$sitename/d" /etc/hosts
    # Add new entry
    echo "$siteip $sitename" | sudo tee -a /etc/hosts
    echo "Arranging for passwordless ssh to container $sitename for user $LOGNAME"
    ssh-copy-id $sitename
    echo "Copying this script to container $sitename"
    scp $0 ${sitename}:
    echo "Now ssh to the container and continue by running '$0 deps' and '$0 install'"
}

do_deps() {
    echo "When prompted for the mysql root password, enter $sqlrootpw"
    sleep 3
    sudo apt-get update
    sudo apt-get install git mysql-client mysql-server php5-mysql php5-cli php5-gd apache2 libapache2-mod-php5 ssmtp
    sudo a2enmod rewrite

    # Configure ssmtp
    sudo tee /etc/ssmtp/ssmtp.conf <<_EOF_
root=postmaster
UseSTARTTLS=YES
hostname=`hostname`
# Edit the following lines
mailhub=mail.$sitedomain
RewriteDomain=$sitedomain
AuthUser=$LOGNAME@$sitedomain
AuthPass=XXXXXXXX
_EOF_

    echo "Adding $LOGNAME to mail group.  Won't take effect until next login."
    sudo sed -i "/mail/s/\$/,$LOGNAME/;s/:,/:/" /etc/group

    echo "Template created in /etc/ssmtp/ssmtp.conf.  Please edit it,"
    echo "log out and back in, and make sure you can send mail using /usr/sbin/sendmail."

    # Ubuntu's drush is too old, https://bugs.launchpad.net/ubuntu/+source/drush/+bug/1530219
    wget http://files.drush.org/drush.phar
    chmod +x drush.phar
    sudo mv drush.phar /usr/local/bin/drush

    # Ubuntu's composer is too old, https://bugs.launchpad.net/bugs/1530204
    wget https://getcomposer.org/download/1.0.0-alpha11/composer.phar
    chmod +x composer.phar
    sudo mv composer.phar /usr/local/bin/composer

    if ! echo $PATH | grep /usr/local/bin
    then
        echo "Please edit ~/.bashrc and add /usr/local/bin to PATH, then log in again"
    fi
}


do_install() {
    if test -d $sitename
    then
        echo "Already installed, aborting"
        exit 1
    fi

    composer create-project drupal/drupal $sitename 8.0.1
    cd $sitename
    sitedir=`pwd`

    drush si standard --site-name=$sitename --db-url=mysql://root:$sqlrootpw@localhost/drupal --account-name=drupal --account-pass=drupal
    # mark files directory world-writable, or themes won't work
    echo "FIXME: removing security on $sitedir/default/files"
    chmod 777 sites/default/files
    chmod 777 sites/default/files/*

    # Configure apache2
    APACHE_LOG_DIR=/var/log/apache2
    sudo tee /etc/apache2/sites-available/$sitename.conf <<_EOF_
<VirtualHost *:80>
        ServerName $sitename
        ServerAdmin webmaster@localhost
        DocumentRoot $sitedir
        ErrorLog ${APACHE_LOG_DIR}/$sitename-error.log
        CustomLog ${APACHE_LOG_DIR}/$sitename-access.log combined
</VirtualHost>

<Directory $sitedir>
Options Indexes FollowSymLinks
AllowOverride All
Require all granted
  RewriteEngine on
    RewriteBase /
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_URI} !=/favicon.ico
    RewriteRule ^ index.php [L]
</Directory>
_EOF_
    sudo ln -s ../sites-available/$sitename.conf /etc/apache2/sites-enabled
    sudo apache2ctl restart
}

case $cmd in
create) do_create;;
deps) do_deps;;
install) do_install;;
*) echo "Usage: $0 create|deps|install"; exit 1;;
esac
