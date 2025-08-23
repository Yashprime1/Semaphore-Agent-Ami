#!/bin/bash 
set -ex pipefail

# Set environment variables for non-interactive installation
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# Function to handle errors
error_handler() {
    echo "ERROR: Script failed at line $1"
    echo "Command that failed: $2"
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

# Install AWS CLI
python3 -m venv prod-venv
source prod-venv/bin/activate
pip3 install awscli --upgrade
deactivate

# Get instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
instance_id=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
security_group_id=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/security-groups | cut -d ' ' -f 1)
key_pair_name=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key | cut -d ' ' -f 3)
region=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)


# Add tags to the packer instance
aws ec2 create-tags --resources $instance_id --region $region --tags \
  Key=packer-name,Value=semaphore-agent-ami-builder \
  Key=instance-id,Value=$instance_id \
  Key=security-group,Value=$security_group_id \
  Key=key-pair,Value=$key_pair_name

echo "Installing semaphoreci tools"

echo "Installing Semaphore CLI..."
# Install Semaphore CLI
curl -L https://github.com/semaphoreci/cli/releases/download/v0.32.0/sem_Linux_x86_64.tar.gz | tar -xz
mv sem /usr/local/bin/
chmod +x /usr/local/bin/sem

echo "Installing SPC (Semaphore Pipeline Compiler)..."
# Install SPC
curl -L https://github.com/semaphoreci/spc/releases/download/v1.12.1/spc_Linux_x86_64.tar.gz | tar -xz
mv spc /usr/local/bin/
chmod +x /usr/local/bin/spc


echo "Installing Erlang..."
apt-get -o DPkg::Lock::Timeout=300 install -f -y
apt-get -o DPkg::Lock::Timeout=300 install -y --allow-change-held-packages linux-libc-dev
apt-get -o DPkg::Lock::Timeout=300 install -y build-essential autoconf libtool libncurses5-dev
curl -L https://github.com/erlang/otp/releases/download/OTP-26.1.2/otp_src_26.1.2.tar.gz | tar -xz
cd otp_src_26.1.2
./configure --prefix=/opt/erlang
make
make install

# Add Erlang to PATH
echo "export PATH=/opt/erlang/bin:\$PATH" >> /etc/profile.d/semaphore.sh
echo "export ERLANG_HOME=/opt/erlang" >> /etc/profile.d/semaphore.sh

echo "Installing When..."
#otp binary needed for when
curl -L https://github.com/renderedtext/when/releases/download/v1.2.1/when_otp_26 -o when_otp_26
mv when_otp_26 /usr/local/bin/when
chmod +x /usr/local/bin/when

echo "SemaphoreCI tools installation completed successfully!"