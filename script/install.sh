# Installing ansible

# Install required packages

echo "Installing required packages ..."

systemctl stop --now apt-daily{,-upgrade}.{timer,service}

systemctl disable --now apt-daily{,-upgrade}.{timer,service}

systemctl kill --kill-who=all apt-daily{,-upgrade}.{timer,service}

# wait until `apt-get updated` has been killed
while ! (systemctl list-units --all apt-daily{,-upgrade}.{timer,service} | egrep -q '(dead|failed)')
do
  sleep 1;
done

sleep 60s;

sudo rm /var/lib/apt/lists/lock

sudo rm /var/cache/apt/archives/lock

sudo rm /var/lib/dpkg/lock

sudo rm /var/lib/dpkg/lock-frontend

echo "Removed lock files ..."

sleep 30s;

sudo apt-get update && sudo apt-get -y upgrade

sleep 30s;
 
sudo apt install -y software-properties-common 
sudo apt-add-repository --yes --update ppa:ansible/ansible 
sudo apt install -y ansible

sleep 30s;
