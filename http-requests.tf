locals {
  dns_command_add    = "chmod +x dnsrequest.sh; ./dnsrequest.sh Add $IP $LABEL $SNOW_AUTH $HOSTNAME"
  dns_command_delete = "echo 'Skipping delete...'"
  script_dir         = "${path.module}/scripts"
}