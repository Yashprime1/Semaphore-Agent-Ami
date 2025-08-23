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

echo "Installing build dependencies"

export JAVA_VERSION_MAJOR=8
export JAVA_VERSION_MINOR=332
export JAVA_VERSION_BUILD=08.1

# Update package lists first
apt-get -o DPkg::Lock::Timeout=300 update -y

# Remove vim if present
apt-get -o DPkg::Lock::Timeout=300 remove vim -y || true

# Fix any broken packages and install essential dependencies
apt-get -o DPkg::Lock::Timeout=300 install -f -y
apt-get -o DPkg::Lock::Timeout=300 install -y --allow-change-held-packages linux-libc-dev

# Install basic packages first
apt-get -o DPkg::Lock::Timeout=300 install -y curl git openssl wget unzip ffmpeg

# Install Python packages
apt-get -o DPkg::Lock::Timeout=300 install -y python3-pip python3-dev python3-venv python3-setuptools

# Install system libraries for headless browser support
apt-get -o DPkg::Lock::Timeout=300 install -y libgbm-dev libxcomposite-dev libxrandr-dev libxkbcommon-dev libpangocairo-1.0-0 libatk1.0-0 libatk-bridge2.0-0

# Install build tools and development libraries
apt-get -o DPkg::Lock::Timeout=300 install -y build-essential autoconf libtool

# Install Java versions
wget https://corretto.aws/downloads/resources/${JAVA_VERSION_MAJOR}.${JAVA_VERSION_MINOR}.${JAVA_VERSION_BUILD}/amazon-corretto-${JAVA_VERSION_MAJOR}.${JAVA_VERSION_MINOR}.${JAVA_VERSION_BUILD}-linux-x64.tar.gz >> /dev/null  \
    &&  tar -xzf amazon-corretto-${JAVA_VERSION_MAJOR}.${JAVA_VERSION_MINOR}.${JAVA_VERSION_BUILD}-linux-x64.tar.gz -C /opt \
    &&  rm -rf amazon-corretto-${JAVA_VERSION_MAJOR}.${JAVA_VERSION_MINOR}.${JAVA_VERSION_BUILD}-linux-x64.tar.gz

cd /tmp  \
    && wget https://corretto.aws/downloads/resources/11.0.19.7.1/amazon-corretto-11.0.19.7.1-linux-x64.tar.gz >> /dev/null  \
    &&  tar -xzf amazon-corretto-11.0.19.7.1-linux-x64.tar.gz -C /opt \
    &&  rm -rf amazon-corretto-11.0.19.7.1-linux-x64.tar.gz

curl --silent https://corretto.aws/downloads/resources/17.0.1.12.1/amazon-corretto-17.0.1.12.1-linux-x64.tar.gz |  tar -C /opt -xzf - && mv /opt/amazon-corretto-17.0.1.12.1-linux-x64 /opt/amazon-corretto-17-linux-x64

curl --silent https://corretto.aws/downloads/resources/18.0.2.9.1/amazon-corretto-18.0.2.9.1-linux-x64.tar.gz |  tar -C /opt -xzf - && mv /opt/amazon-corretto-18.0.2.9.1-linux-x64 /opt/amazon-corretto-18-linux-x64

# Install Firefox for test cafe
mkdir -p /usr/lib/firefox
wget --no-verbose https://ftp.mozilla.org/pub/firefox/releases/130.0/linux-x86_64/en-US/firefox-130.0.tar.bz2
tar -xjf firefox-130.0.tar.bz2 -C /usr/lib/firefox
ln -s /usr/lib/firefox/firefox/firefox /usr/bin/firefox
rm -rf firefox-130.0.tar.bz2

# Install git lfs
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
apt-get install git-lfs
git lfs install

# Install Apache Ant
curl -s https://archive.apache.org/dist/ant/binaries/apache-ant-1.9.3-bin.tar.gz |   tar -v -xz -C /opt/

# Install Go
curl -s https://dl.google.com/go/go1.19.3.linux-amd64.tar.gz| tar -v -C /opt/ -xz

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install jq from official source (version 1.7.1)
curl -L https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux64 -o /usr/local/bin/jq
chmod +x /usr/local/bin/jq
ln -sf /usr/local/bin/jq /usr/bin/jq

# Install Google Chrome for test cafe
wget --no-verbose -O /tmp/chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_135.0.7049.114-1_amd64.deb \
  && apt install -y /tmp/chrome.deb \
  && rm /tmp/chrome.deb

# Install Node.js and npm
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Yarn
npm install --global yarn

# Install JFrog CLI
curl -fL https://getcli.jfrog.io | sh &&  mv jfrog /usr/bin/ &&  chmod +x /usr/bin/jfrog

echo "Set maven, java and ant home directories in PATH"
# Create the semaphore.sh file if it doesn't exist
touch /etc/profile.d/semaphore.sh
chmod 644 /etc/profile.d/semaphore.sh

# Set Java and Maven environment variables
echo "export JAVA_HOME=/opt/amazon-corretto-8.332.08.1-linux-x64" >> /etc/profile.d/semaphore.sh
echo "export M2_HOME=/opt/apache-maven-3.9.4" >> /etc/profile.d/semaphore.sh
echo "export MAVEN_HOME=/opt/apache-maven-3.9.4" >> /etc/profile.d/semaphore.sh
echo 'export PATH=/opt/amazon-corretto-11.0.19.7.1-linux-x64/bin:/opt/apache-maven-3.9.4/bin:$PATH' >> /etc/profile.d/semaphore.sh

echo "fs.file-max=1000000" >> /etc/sysctl.conf
ls -lrth /etc/sysctl.conf
ls -lrth /etc/security/limits.conf
echo "semaphore           soft    nofile          900000" >> /etc/security/limits.conf
echo "semaphore           hard    nofile          900000" >> /etc/security/limits.conf

mkdir -p /home/semaphore/semaphore-agent-home/logs
chown -R semaphore:users /home/semaphore/semaphore-agent-home

echo "Ultron ami bootstrap completed successfully!"
