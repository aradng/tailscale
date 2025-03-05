#!/bin/bash

# Function to print messages in color
print_green() {
  echo -e "\e[32m$1\e[0m"
}

print_red() {
  echo -e "\e[31m$1\e[0m"
}

# Function to exit on error
error_exit() {
  print_red "ERROR: $1"
  exit 1
}

# Validate subnet using ipcalc
validate_subnet() {
  local subnet=$1
  OUTPUT=$(ipcalc -n "$subnet" 2>&1)
  if echo "$OUTPUT" | grep -iq "INVALID"; then
    return 1  # Invalid subnet
  else
    return 0  # Valid subnet
  fi
}
# Update repositories and install dependencies with error handling
echo "Updating repositories..."
sudo apt update -qq >/dev/null 2>&1 || error_exit "Failed to update repositories"

echo "Installing dependencies..."
sudo apt install -qq -y ipcalc >/dev/null 2>&1 || error_exit "Failed to install ipcalc"

# INFER DEFAULT SUBNET
IFACE=$(ip -o -f inet route | grep -m 1 "default.*dev" | awk '{print $5}')
CIDR=$(ip -o -f inet addr show | grep -m 1 $IFACE | awk '/scope global/ {print $4}')
SUBNET=$(ipcalc -n $CIDR | grep Network | awk '{print $2}')

# Ask for user input
while true; do
  read -p "Confirm inferred subnet ($SUBNET) or enter a new one: " USER_SUBNET
  USER_SUBNET=${USER_SUBNET:-$SUBNET}
  if validate_subnet "$USER_SUBNET"; then
    SUBNET=$USER_SUBNET
    break
  else
    print_red "Invalid subnet: $USER_SUBNET. Please enter a valid CIDR."
  fi
done

print_green "Using subnet: $SUBNET"

# Apply UFW rules and check the result
apply_and_check() {
  local rule=$1
  local description=$2

  # Run the ufw rule and analyze its output
  OUTPUT=$(sudo ufw $rule 2>&1)

  if echo "$OUTPUT" | grep -iq "Skipping"; then
    print_green "$description: exists"
  elif echo "$OUTPUT" | grep -iq "Rules updated"; then
    print_green "$description: added"
  elif echo "$OUTPUT" | grep -iq "Default .* policy changed"; then
    print_green "$description: Default policy changed"
  else
    print_red "$description: Error adding rule"
  fi
}

echo "Adding rules..."

# Reject instead of Deny
apply_and_check "default reject incoming" "incoming (reject incoming)"

# Docker
apply_and_check "default allow routed" "Docker (allow routed)"

# Web
apply_and_check "allow http" "HTTP (port 80)"
apply_and_check "allow https" "HTTPS (port 443)"

# SSH
apply_and_check "allow OpenSSH" "OpenSSH"

# Subnet
apply_and_check "allow from $SUBNET" "Allow from subnet $SUBNET"

# Enable UFW if not already enabled
if sudo ufw status | grep -iq "Status: active"; then
  print_green "UFW is already active"
else
  sudo ufw --force enable >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    print_green "UFW is now enabled"
  else
    print_red "Failed to enable UFW"
  fi
fi

# Final confirmation and immediate exit
print_green "All tasks completed successfully."
exit 0
