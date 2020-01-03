#!/usr/bin/env bash

##############
# Install deps
##############
# Ubuntu
apt-get update
apt-get install python-pip jq -y
#####################

# Amazon Linux (RHEL) - NAT instances
yum update -y
# epel provides python-pip & jq
yum install -y epel-release
yum install python-pip jq -y
#####################

pip install --upgrade awscli

##############

cat <<"EOF" > /home/${ssh_user}/update_ssh_authorized_keys.sh
#!/usr/bin/env bash

set -e

BUCKET_NAME=${s3_bucket_name}
BUCKET_URI=${s3_bucket_uri}
SSH_USER=${ssh_user}
MARKER="# KEYS_BELOW_WILL_BE_UPDATED_BY_TERRAFORM"
KEYS_FILE=/home/$SSH_USER/.ssh/authorized_keys
TEMP_KEYS_FILE=$(mktemp /tmp/authorized_keys.XXXXXX)
PUB_KEYS_DIR=/home/$SSH_USER/pub_key_files/
PATH=/usr/local/bin:$PATH

[[ -z $BUCKET_URI ]] && BUCKET_URI="s3://$BUCKET_NAME/"

mkdir -p $PUB_KEYS_DIR

# Add marker, if not present, and copy static content.
grep -Fxq "$MARKER" $KEYS_FILE || echo -e "\n$MARKER" >> $KEYS_FILE
line=$(grep -n "$MARKER" $KEYS_FILE | cut -d ":" -f 1)
head -n $line $KEYS_FILE > $TEMP_KEYS_FILE

# Synchronize the keys from the bucket.
aws s3 sync --delete $BUCKET_URI $PUB_KEYS_DIR
for filename in $PUB_KEYS_DIR/*; do
    sed 's/\n\?$/\n/' < $filename >> $TEMP_KEYS_FILE
done

# Move the new authorized keys in place.
chown $SSH_USER:$SSH_USER $KEYS_FILE
chmod 600 $KEYS_FILE
mv $TEMP_KEYS_FILE $KEYS_FILE
if [[ $(command -v "selinuxenabled") ]]; then
    restorecon -R -v $KEYS_FILE
fi
EOF

cat <<"EOF" > /home/${ssh_user}/.ssh/config
Host *
    StrictHostKeyChecking no
EOF
chmod 600 /home/${ssh_user}/.ssh/config
chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh/config

chown ${ssh_user}:${ssh_user} /home/${ssh_user}/update_ssh_authorized_keys.sh
chmod 755 /home/${ssh_user}/update_ssh_authorized_keys.sh

# Execute now
su ${ssh_user} -c /home/${ssh_user}/update_ssh_authorized_keys.sh

# Be backwards compatible with old cron update enabler
if [ "${enable_hourly_cron_updates}" = 'true' -a -z "${keys_update_frequency}" ]; then
  keys_update_frequency="0 * * * *"
else
  keys_update_frequency="${keys_update_frequency}"
fi

# Add to cron
if [ -n "$keys_update_frequency" ]; then
  croncmd="/home/${ssh_user}/update_ssh_authorized_keys.sh"
  cronjob="$keys_update_frequency $croncmd"
  ( crontab -u ${ssh_user} -l | grep -v "$croncmd" ; echo "$cronjob" ) | crontab -u ${ssh_user} -
fi

# Append addition user-data script
${additional_user_data_script}

# Ammend SSH Server config
sed -i '/ClientAliveInterval/c\ClientAliveInterval 120' /etc/ssh/sshd_config
service sshd restart

mkdir -p /etc/pki/tls/certs
cd /etc/pki/tls/certs && curl --remote-name https://raw.githubusercontent.com/logzio/public-certificates/master/COMODORSADomainValidationSecureServerCA.crt

# Add filebeat Log Shipping
cat <<"EOF" > /etc/yum.repos.d/elastic.repo
[elastic-5.x]
name=Elastic repository for 5.x packages
baseurl=https://artifacts.elastic.co/packages/5.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

chmod 600 /etc/yum.repos.d/elastic.repo

export REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`;

if [ "$REGION" == 'us-west-2' ]
then 
  export LOGZ_IO_TOKEN='AQICAHiDBkJiH3QYQ4Rv8n6/c6Y1kPQVv+LEKbAy+t3SciI3IAGRd+jeoRUfCTy5ZmmnqRNaAAAAfzB9BgkqhkiG9w0BBwagcDBuAgEAMGkGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMNF1KgzG6wqhUYevtAgEQgDz1bekkU9WVhvkXQ14SZM4mwe5ngpmZSCO36UCZpdQPug+5x0dRxDx5SPrz9CABY30VytTmAesCZ4C/3ww=';
elif [ "$REGION" == 'eu-west-2' ]
then
  export LOGZ_IO_TOKEN='AQICAHiiqpN2wotehUQMG7jBvp0bACrsg4ixqQGtbhSZSg8D/wF0CQUkSlbVhw634jomykBJAAAAfzB9BgkqhkiG9w0BBwagcDBuAgEAMGkGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMuuW1VfLgo35AfXtLAgEQgDwncfsgl42uPN0WTpypq75/0gviqgsBXJ81zPiu0agu0rxEN8mjwuLQw0d3qzxZb3fbZCD5kQ/DKlezEks=';
fi

export LOGZ_IO_TOKEN=`aws kms decrypt --region $REGION --ciphertext-blob fileb://<(echo $LOGZ_IO_TOKEN | base64 -d) --output text --query Plaintext | base64 -d`;

yum -y install filebeat
cat <<EOF > /etc/filebeat/filebeat.yml
############################# Filebeat #####################################

filebeat:
  prospectors:
  - input_type: log
    paths:
      - /var/log/secure
    fields:
      logzio_codec: plain
      token: $LOGZ_IO_TOKEN
      type: secure
    fields_under_root: true
    encoding: utf-8
    ignore_older: 3h

#For version 6.x and lower
    registry_file: /var/lib/filebeat/registry
    
############################# Output ##########################################

output:
  logstash:
    hosts: ["listener-eu.logz.io:5015"]  
    ssl:
      certificate_authorities: ['/etc/pki/tls/certs/COMODORSADomainValidationSecureServerCA.crt']
EOF

chmod 600 /etc/filebeat/filebeat.yml
chkconfig filebeat on
service filebeat start
