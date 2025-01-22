#/usr/bin/env bash

source /etc/profile

SETUP="/usr/comma/setup"
RESET="/usr/comma/reset"
CONTINUE="/data/continue.sh"
INSTALLER="/tmp/installer"
RESET_TRIGGER="/data/__system_reset__"

echo "waiting for weston"
for i in {1..200}; do
  if systemctl is-active --quiet weston-ready; then
    break
  fi
  sleep 0.1
done

if systemctl is-active --quiet weston-ready; then
  echo "weston ready after ${SECONDS}s"
else
  echo "timed out waiting for weston, ${SECONDS}s"
fi

sudo chown comma: /data
sudo chown comma: /data/media

handle_setup_keys () {
  # install default SSH key while still in setup
  if [[ ! -e /data/params/d/GithubSshKeys && ! -e /data/continue.sh ]]; then
    if [ ! -e /data/params/d ]; then
      mkdir -p /data/params/d_tmp
      ln -s /data/params/d_tmp /data/params/d
    fi

    echo -n 1 > /data/params/d/SshEnabled
    cp /usr/comma/setup_keys /data/params/d/GithubSshKeys
  elif [[ -e /data/params/d/GithubSshKeys && -e /data/continue.sh ]]; then
    if cmp -s /data/params/d/GithubSshKeys /usr/comma/setup_keys; then
      rm /data/params/d/SshEnabled
      rm /data/params/d/GithubSshKeys
    fi
  fi
}

handle_adb () {
  sudo mount -o remount,rw /
  sudo systemctl start adbd

  # Check if /config is already mounted
  if ! mountpoint -q /config; then
    sudo mkdir -p /config
    sudo mount -t configfs none /config
  else
    echo "/config is already mounted."
  fi

  # Create USB gadget directory structure
  sudo mkdir -p /config/usb_gadget/g1
  cd /config/usb_gadget/g1
  sudo mkdir -p strings/0x409
  sudo mkdir -p configs/c.1/strings/0x409
  sudo mkdir -p functions/ncm.0

  # Set Vendor and Product ID
  echo 0x04D8 | sudo tee idVendor
  echo 0x1234 | sudo tee idProduct

  # Set strings
  echo "0123456789" | sudo tee strings/0x409/serialnumber
  echo "Microchip Technology, Inc." | sudo tee strings/0x409/manufacturer
  echo "Linux USB Gadget" | sudo tee strings/0x409/product
  echo 250 | sudo tee configs/c.1/MaxPower

  echo "NCM" | sudo tee configs/c.1/strings/0x409/configuration
  sudo rm -f configs/c.1/ncm.0
  sudo ln -s functions/ncm.0 configs/c.1/

  # Enable the gadget
  ls /sys/class/udc | sudo tee UDC
}

# factory reset handling
if [ -f "$RESET_TRIGGER" ]; then
  echo "launching system reset, reset trigger present"
  rm -f $RESET_TRIGGER
  $RESET
elif (( "$(cat /sys/devices/platform/soc/894000.i2c/i2c-2/2-0017/touch_count)" > 4 )); then
  echo "launching system reset, got taps"
  $RESET
elif ! mountpoint -q /data; then
  echo "userdata not mounted. loading system reset"
  if [ "$(head -c 15 /dev/disk/by-partlabel/userdata)" == "COMMA_RESET" ]; then
    $RESET --format
  else
    $RESET --recover
  fi
fi

# setup /data/tmp
rm -rf /data/tmp
mkdir -p /data/tmp

# symlink vscode to userdata
mkdir -p /data/tmp/vscode-server
ln -s /data/tmp/vscode-server ~/.vscode-server
ln -s /data/tmp/vscode-server ~/.cursor-server

while true; do
  pkill -f "$SETUP"
  handle_setup_keys

  echo "adb setup"
  handle_adb

  if [ -f $CONTINUE ]; then
    exec "$CONTINUE"
  fi

  sudo abctl --set_success

  # cleanup installers from previous runs
  rm -f $INSTALLER
  pkill -f $INSTALLER

  # run setup and wait for installer
  $SETUP &
  echo "waiting for installer"
  while [ ! -f $INSTALLER ]; do
    sleep 1
  done

  # run installer and wait for continue.sh
  chmod +x $INSTALLER
  $INSTALLER &
  echo "running installer"
  while [ ! -f $CONTINUE ] && ps -p $! > /dev/null; do
    sleep 1
  done
done
