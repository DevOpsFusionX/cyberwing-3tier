#!/usr/bin/env bash
# ============================================================================
#  Cyberwing.pk — Azure manual deployment helper
#  Ek hi script jo handout ke Phase 3–4 ke saare `az` commands chala deti hai.
#
#  Usage:
#     chmod +x azure/deploy.sh
#     ./azure/deploy.sh
#
#  Zaroorat: Azure CLI (az login ho chuka ho), aur SSH public key
#  NOTE: Yeh script sirf seekhne ke liye hai — production mein IaC (Terraform/Bicep)
#        use karein. Har step dobara chalana safe hai (idempotent jaisa).
# ============================================================================
set -euo pipefail

# ----------------------------- settings -------------------------------------
RG="${RG:-rg-cyberwing-lab}"
LOC="${LOC:-uaenorth}"
VM="${VM:-vm-cyberwing}"
VNET="${VNET:-vnet-cyberwing}"
SUBNET="${SUBNET:-snet-web}"
NSG="${NSG:-nsg-cyberwing}"
PIP="${PIP:-pip-cyberwing}"
NIC="${NIC:-nic-cyberwing}"
SIZE="${SIZE:-Standard_B2als_v2}"
IMAGE="${IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
ADMIN="${ADMIN:-azureuser}"
KEY="${KEY:-$HOME/.ssh/cyberwing-key.pub}"
DISK_GB="${DISK_GB:-64}"
CLOUD_INIT="${CLOUD_INIT:-azure/cloud-init.yaml}"

say() { printf "\n\033[1;35m==> %s\033[0m\n" "$*"; }
ok()  { printf "    \033[0;32m✓ %s\033[0m\n" "$*"; }

# ----------------------------- checks ---------------------------------------
command -v az >/dev/null || { echo "az CLI nahi mila. Phase 1 dekhein."; exit 1; }
az account show >/dev/null 2>&1 || { echo "Pehle 'az login' chalayein."; exit 1; }
[ -f "$KEY" ] || { echo "SSH public key nahi mili: $KEY"; echo "Banao: ssh-keygen -t ed25519 -f ~/.ssh/cyberwing-key"; exit 1; }
[ -f "$CLOUD_INIT" ] || { echo "cloud-init file nahi mili: $CLOUD_INIT (repo root se chalayein)"; exit 1; }

MYIP="$(curl -s https://api.ipify.org)"
say "Aap ki public IP: $MYIP  (SSH/Jenkins/Grafana sirf isi IP se khulenge)"
az account show --query "{Subscription:name, Id:id, User:user.name}" -o table

read -r -p "Aage barhna hai? (yes/no) " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Cancel."; exit 0; }

# ----------------------------- providers ------------------------------------
say "Resource providers register (agar pehle se hain to skip)"
for ns in Microsoft.Compute Microsoft.Network; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "")
  if [ "$state" != "Registered" ]; then
    az provider register --namespace "$ns"
    ok "$ns register ho gaya"
  else
    ok "$ns pehle se Registered"
  fi
done

# ----------------------------- resource group -------------------------------
say "1) Resource group: $RG ($LOC)"
az group create --name "$RG" --location "$LOC" -o table
ok "RG ready"

# ----------------------------- network --------------------------------------
say "2) VNet + subnet"
az network vnet create -g "$RG" -n "$VNET" -l "$LOC" \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefixes 10.10.1.0/24 -o table >/dev/null
ok "$VNET / $SUBNET ready"

say "3) NSG + rules"
az network nsg create -g "$RG" -n "$NSG" -l "$LOC" -o table >/dev/null
add_rule() { # name priority ports source
  az network nsg rule create -g "$RG" --nsg-name "$NSG" -n "$1" --priority "$2" \
    --direction Inbound --access Allow --protocol Tcp \
    --destination-port-ranges $3 --source-address-prefixes "$4" -o table >/dev/null 2>&1 \
    && ok "rule $1 ($3 <- $4)" || ok "rule $1 pehle se maujood"
}
add_rule allow-http          100 "80"            "*"
add_rule allow-https         110 "443"           "*"
add_rule allow-mgmt-from-my-ip 120 "22 8080 3000" "$MYIP/32"

say "4) Public IP (Standard, Static)"
az network public-ip create -g "$RG" -n "$PIP" -l "$LOC" \
  --sku Standard --allocation-method Static -o table >/dev/null
PUBIP=$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)
ok "Public IP: $PUBIP"

say "5) NIC"
az network nic create -g "$RG" -n "$NIC" -l "$LOC" \
  --vnet-name "$VNET" --subnet "$SUBNET" \
  --public-ip-address "$PIP" --network-security-group "$NSG" -o table >/dev/null
ok "NIC ready"

# ----------------------------- VM -------------------------------------------
say "6) VM ($SIZE) + cloud-init"
az vm create -g "$RG" -n "$VM" -l "$LOC" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --admin-username "$ADMIN" \
  --ssh-key-values "$KEY" \
  --nics "$NIC" \
  --os-disk-size-gb "$DISK_GB" \
  --storage-sku StandardSSD_LRS \
  --custom-data "@$CLOUD_INIT" \
  --output table

ok "VM ban gayi"

# ----------------------------- done -----------------------------------------
cat <<EOF

────────────────────────────────────────────────────────────
  ✅ Infrastructure tayyar!

  App       : http://$PUBIP      (cloud-init ke baad)
  Jenkins   : http://$PUBIP:8080
  Grafana   : http://$PUBIP:3000
  SSH       : ssh -i ${KEY%.pub} $ADMIN@$PUBIP

  Agli commands (laptop par):
     ssh -i ${KEY%.pub} $ADMIN@$PUBIP
     cloud-init status --wait          # 'done' aane tak intezar
     exit && ssh -i ${KEY%.pub} $ADMIN@$PUBIP   # docker group ka asar
     docker ps

  Kharcha band karne ke liye (aakhir mein):
     az group delete -n $RG --yes --no-wait
────────────────────────────────────────────────────────────
EOF
